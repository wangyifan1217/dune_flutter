#include "screenshot_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <wingdi.h>
#include <wincodec.h>
#include <windowsx.h>  // For GET_X_LPARAM and GET_Y_LPARAM

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <vector>
#include <cstdio>
#include <cstdlib>
#include <optional>

#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "msimg32.lib")  // AlphaBlend

namespace screenshot {

// Helper function to encode HBITMAP to PNG bytes using WIC
std::vector<uint8_t> EncodeBitmapToPNG(HBITMAP hBitmap, int width, int height) {
  std::vector<uint8_t> pngBytes;
  
  // Initialize COM
  HRESULT hr = CoInitialize(nullptr);
  bool comInitialized = SUCCEEDED(hr);
  
  IWICImagingFactory* pFactory = nullptr;
  IWICBitmap* pWICBitmap = nullptr;
  IWICStream* pStream = nullptr;
  IWICBitmapEncoder* pEncoder = nullptr;
  IWICBitmapFrameEncode* pFrameEncode = nullptr;
  
  do {
    // Create WIC factory
    hr = CoCreateInstance(
      CLSID_WICImagingFactory,
      nullptr,
      CLSCTX_INPROC_SERVER,
      IID_IWICImagingFactory,
      reinterpret_cast<LPVOID*>(&pFactory)
    );
    if (FAILED(hr)) break;
    
    // Create WIC bitmap from HBITMAP
    hr = pFactory->CreateBitmapFromHBITMAP(hBitmap, nullptr, WICBitmapUseAlpha, &pWICBitmap);
    if (FAILED(hr)) break;
    
    // Create WIC stream
    hr = pFactory->CreateStream(&pStream);
    if (FAILED(hr)) break;
    
    // Create memory stream using IStream
    IStream* pMemStream = nullptr;
    hr = CreateStreamOnHGlobal(nullptr, TRUE, &pMemStream);
    if (FAILED(hr)) break;
    
    // Initialize WIC stream from IStream
    hr = pStream->InitializeFromIStream(pMemStream);
    pMemStream->Release();
    if (FAILED(hr)) break;
    
    // Create PNG encoder
    hr = pFactory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &pEncoder);
    if (FAILED(hr)) break;
    
    hr = pEncoder->Initialize(pStream, WICBitmapEncoderNoCache);
    if (FAILED(hr)) break;
    
    // Create frame
    hr = pEncoder->CreateNewFrame(&pFrameEncode, nullptr);
    if (FAILED(hr)) break;
    
    hr = pFrameEncode->Initialize(nullptr);
    if (FAILED(hr)) break;
    
    hr = pFrameEncode->SetSize(width, height);
    if (FAILED(hr)) break;
    
    WICPixelFormatGUID formatGUID = GUID_WICPixelFormat32bppBGRA;
    hr = pFrameEncode->SetPixelFormat(&formatGUID);
    if (FAILED(hr)) break;
    
    hr = pFrameEncode->WriteSource(pWICBitmap, nullptr);
    if (FAILED(hr)) break;
    
    hr = pFrameEncode->Commit();
    if (FAILED(hr)) break;
    
    hr = pEncoder->Commit();
    if (FAILED(hr)) break;
    
    // Get data from stream
    ULARGE_INTEGER streamSize;
    IStream* pIStream = nullptr;
    hr = pStream->QueryInterface(IID_IStream, reinterpret_cast<void**>(&pIStream));
    if (SUCCEEDED(hr)) {
      STATSTG stat;
      if (SUCCEEDED(pIStream->Stat(&stat, STATFLAG_NONAME))) {
        streamSize = stat.cbSize;
        pngBytes.resize(static_cast<size_t>(streamSize.QuadPart));
        
        LARGE_INTEGER zero = {};
        pIStream->Seek(zero, STREAM_SEEK_SET, nullptr);
        
        ULONG bytesRead = 0;
        pIStream->Read(pngBytes.data(), static_cast<ULONG>(pngBytes.size()), &bytesRead);
      }
      pIStream->Release();
    }
    
  } while (false);
  
  // Cleanup
  if (pFrameEncode) pFrameEncode->Release();
  if (pEncoder) pEncoder->Release();
  if (pStream) pStream->Release();
  if (pWICBitmap) pWICBitmap->Release();
  if (pFactory) pFactory->Release();
  
  if (comInitialized) {
    CoUninitialize();
  }
  
  return pngBytes;
}

// Capture virtual desktop (all monitors) to HBITMAP.
// Bitmap origin (0,0) maps to (SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN).
HBITMAP CaptureScreenToBitmap(int* width, int* height, bool includeCursor) {
  SetProcessDPIAware();

  HDC hdcScreen = GetDC(nullptr);
  if (!hdcScreen) return nullptr;

  const int virtualX = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int virtualY = GetSystemMetrics(SM_YVIRTUALSCREEN);
  *width = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  *height = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (*width <= 0 || *height <= 0) {
    *width = GetSystemMetrics(SM_CXSCREEN);
    *height = GetSystemMetrics(SM_CYSCREEN);
  }

  HDC hdcMemory = CreateCompatibleDC(hdcScreen);
  if (!hdcMemory) {
    ReleaseDC(nullptr, hdcScreen);
    return nullptr;
  }

  HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, *width, *height);
  if (!hBitmap) {
    DeleteDC(hdcMemory);
    ReleaseDC(nullptr, hdcScreen);
    return nullptr;
  }

  HBITMAP hOldBitmap = static_cast<HBITMAP>(SelectObject(hdcMemory, hBitmap));

  if (!BitBlt(hdcMemory, 0, 0, *width, *height, hdcScreen, virtualX, virtualY,
              SRCCOPY)) {
    SelectObject(hdcMemory, hOldBitmap);
    DeleteObject(hBitmap);
    DeleteDC(hdcMemory);
    ReleaseDC(nullptr, hdcScreen);
    return nullptr;
  }

  if (includeCursor) {
    CURSORINFO cursorInfo = {};
    cursorInfo.cbSize = sizeof(CURSORINFO);

    if (GetCursorInfo(&cursorInfo) && (cursorInfo.flags & CURSOR_SHOWING)) {
      ICONINFO iconInfo;
      if (GetIconInfo(cursorInfo.hCursor, &iconInfo)) {
        POINT pt;
        GetCursorPos(&pt);
        const int x = pt.x - iconInfo.xHotspot - virtualX;
        const int y = pt.y - iconInfo.yHotspot - virtualY;

        DrawIconEx(hdcMemory, x, y, cursorInfo.hCursor, 0, 0, 0, nullptr,
                   DI_NORMAL);

        if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
        if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
      }
    }
  }

  SelectObject(hdcMemory, hOldBitmap);
  DeleteDC(hdcMemory);
  ReleaseDC(nullptr, hdcScreen);

  return hBitmap;
}

// WeChat-style region capture: freeze screen → dark mask → clear preview →
// drag to select → release to confirm (resize handles) → Enter/double-click done.
enum class OverlayPhase {
  Idle,
  Selecting,
  Confirmed,
};

enum class HitZone {
  None = 0,
  Move,
  N, S, E, W,
  NE, NW, SE, SW,
};

struct SelectionState {
  POINT startPoint{};
  POINT currentPoint{};
  POINT dragOrigin{};
  RECT selectedRect{};
  RECT dragOriginRect{};
  OverlayPhase phase = OverlayPhase::Idle;
  HitZone activeHit = HitZone::None;
  bool cancelled = false;
  bool finished = false;
  HBITMAP frozenBitmap = nullptr;
  int screenWidth = 0;
  int screenHeight = 0;
  DWORD lastClickTick = 0;
  POINT lastClickPt{};
};

static SelectionState* g_selectionState = nullptr;
static constexpr int kHandleSize = 8;
static constexpr int kMinSelSize = 4;

static RECT NormalizedRect(POINT a, POINT b) {
  RECT r;
  r.left = min(a.x, b.x);
  r.top = min(a.y, b.y);
  r.right = max(a.x, b.x);
  r.bottom = max(a.y, b.y);
  return r;
}

static RECT ClampRectToScreen(RECT r, int sw, int sh) {
  if (r.left < 0) r.left = 0;
  if (r.top < 0) r.top = 0;
  if (r.right > sw) r.right = sw;
  if (r.bottom > sh) r.bottom = sh;
  if (r.right - r.left < kMinSelSize) {
    r.right = min(sw, r.left + kMinSelSize);
  }
  if (r.bottom - r.top < kMinSelSize) {
    r.bottom = min(sh, r.top + kMinSelSize);
  }
  return r;
}

static bool PtInRectInflated(const RECT& r, int x, int y, int pad) {
  return x >= r.left - pad && x <= r.right + pad &&
         y >= r.top - pad && y <= r.bottom + pad;
}

static HitZone HitTestSelection(const RECT& r, int x, int y) {
  const int hs = kHandleSize + 2;
  auto nearPt = [&](int px, int py) {
    return abs(x - px) <= hs && abs(y - py) <= hs;
  };
  if (nearPt(r.left, r.top)) return HitZone::NW;
  if (nearPt(r.right, r.top)) return HitZone::NE;
  if (nearPt(r.left, r.bottom)) return HitZone::SW;
  if (nearPt(r.right, r.bottom)) return HitZone::SE;
  if (nearPt((r.left + r.right) / 2, r.top)) return HitZone::N;
  if (nearPt((r.left + r.right) / 2, r.bottom)) return HitZone::S;
  if (nearPt(r.left, (r.top + r.bottom) / 2)) return HitZone::W;
  if (nearPt(r.right, (r.top + r.bottom) / 2)) return HitZone::E;
  if (x > r.left && x < r.right && y > r.top && y < r.bottom) {
    return HitZone::Move;
  }
  return HitZone::None;
}

static void ApplyHitDrag(RECT* r, HitZone hit, int dx, int dy, int sw, int sh) {
  RECT next = *r;
  switch (hit) {
    case HitZone::Move:
      next.left += dx;
      next.right += dx;
      next.top += dy;
      next.bottom += dy;
      break;
    case HitZone::N:
      next.top += dy;
      break;
    case HitZone::S:
      next.bottom += dy;
      break;
    case HitZone::W:
      next.left += dx;
      break;
    case HitZone::E:
      next.right += dx;
      break;
    case HitZone::NW:
      next.left += dx;
      next.top += dy;
      break;
    case HitZone::NE:
      next.right += dx;
      next.top += dy;
      break;
    case HitZone::SW:
      next.left += dx;
      next.bottom += dy;
      break;
    case HitZone::SE:
      next.right += dx;
      next.bottom += dy;
      break;
    default:
      break;
  }
  if (next.right < next.left + kMinSelSize) {
    if (hit == HitZone::W || hit == HitZone::NW || hit == HitZone::SW) {
      next.left = next.right - kMinSelSize;
    } else {
      next.right = next.left + kMinSelSize;
    }
  }
  if (next.bottom < next.top + kMinSelSize) {
    if (hit == HitZone::N || hit == HitZone::NW || hit == HitZone::NE) {
      next.top = next.bottom - kMinSelSize;
    } else {
      next.bottom = next.top + kMinSelSize;
    }
  }
  *r = ClampRectToScreen(next, sw, sh);
}

static void DrawHandle(HDC hdc, int cx, int cy) {
  RECT hr = {cx - kHandleSize / 2, cy - kHandleSize / 2,
             cx + kHandleSize / 2 + 1, cy + kHandleSize / 2 + 1};
  HBRUSH fill = CreateSolidBrush(RGB(255, 255, 255));
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(7, 193, 96));  // WeChat green
  HGDIOBJ oldBrush = SelectObject(hdc, fill);
  HGDIOBJ oldPen = SelectObject(hdc, pen);
  Rectangle(hdc, hr.left, hr.top, hr.right, hr.bottom);
  SelectObject(hdc, oldBrush);
  SelectObject(hdc, oldPen);
  DeleteObject(fill);
  DeleteObject(pen);
}

static void DrawSelectionChrome(HDC hdc, const RECT& sel, bool showHandles) {
  const int left = sel.left;
  const int top = sel.top;
  const int right = sel.right;
  const int bottom = sel.bottom;

  HPEN hPen = CreatePen(PS_SOLID, 2, RGB(7, 193, 96));
  HGDIOBJ oldPen = SelectObject(hdc, hPen);
  HGDIOBJ oldBrush = SelectObject(hdc, GetStockObject(NULL_BRUSH));
  Rectangle(hdc, left, top, right, bottom);
  SelectObject(hdc, oldBrush);
  SelectObject(hdc, oldPen);
  DeleteObject(hPen);

  if (showHandles) {
    DrawHandle(hdc, left, top);
    DrawHandle(hdc, right, top);
    DrawHandle(hdc, left, bottom);
    DrawHandle(hdc, right, bottom);
    DrawHandle(hdc, (left + right) / 2, top);
    DrawHandle(hdc, (left + right) / 2, bottom);
    DrawHandle(hdc, left, (top + bottom) / 2);
    DrawHandle(hdc, right, (top + bottom) / 2);
  }

  // Size tip (WeChat-like)
  wchar_t tip[64];
  swprintf_s(tip, L"%d × %d", max(0, right - left), max(0, bottom - top));
  SIZE tipSize{};
  HFONT font = CreateFontW(16, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                           DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  HGDIOBJ oldFont = SelectObject(hdc, font);
  GetTextExtentPoint32W(hdc, tip, lstrlenW(tip), &tipSize);
  int tipX = left;
  int tipY = top - tipSize.cy - 10;
  if (tipY < 4) tipY = bottom + 8;
  RECT tipBg = {tipX, tipY, tipX + tipSize.cx + 12, tipY + tipSize.cy + 6};
  HBRUSH tipBrush = CreateSolidBrush(RGB(0, 0, 0));
  FillRect(hdc, &tipBg, tipBrush);
  DeleteObject(tipBrush);
  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, RGB(255, 255, 255));
  TextOutW(hdc, tipX + 6, tipY + 3, tip, lstrlenW(tip));
  SelectObject(hdc, oldFont);
  DeleteObject(font);

  if (showHandles) {
    const wchar_t* hint = L"Enter / 双击完成 · Esc 取消";
    SIZE hintSize{};
    HFONT hintFont = CreateFontW(14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                                 DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                                 CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                 DEFAULT_PITCH | FF_SWISS, L"Microsoft YaHei UI");
    HGDIOBJ oldHintFont = SelectObject(hdc, hintFont);
    GetTextExtentPoint32W(hdc, hint, lstrlenW(hint), &hintSize);
    int hx = right - hintSize.cx - 12;
    if (hx < left) hx = left;
    int hy = bottom + 10;
    if (hy + hintSize.cy + 6 > g_selectionState->screenHeight) {
      hy = top - hintSize.cy - 12;
    }
    RECT hintBg = {hx, hy, hx + hintSize.cx + 12, hy + hintSize.cy + 6};
    HBRUSH hintBrush = CreateSolidBrush(RGB(0, 0, 0));
    FillRect(hdc, &hintBg, hintBrush);
    DeleteObject(hintBrush);
    SetTextColor(hdc, RGB(220, 220, 220));
    TextOutW(hdc, hx + 6, hy + 3, hint, lstrlenW(hint));
    SelectObject(hdc, oldHintFont);
    DeleteObject(hintFont);
  }
}

static void PaintOverlay(HWND hwnd, HDC hdc) {
  if (!g_selectionState || !g_selectionState->frozenBitmap) return;

  RECT clientRect;
  GetClientRect(hwnd, &clientRect);
  const int width = clientRect.right - clientRect.left;
  const int height = clientRect.bottom - clientRect.top;

  HDC hdcMem = CreateCompatibleDC(hdc);
  HBITMAP hbmMem = CreateCompatibleBitmap(hdc, width, height);
  HBITMAP hbmOld = static_cast<HBITMAP>(SelectObject(hdcMem, hbmMem));

  // Base: frozen screen
  HDC hdcFrozen = CreateCompatibleDC(hdc);
  HBITMAP oldFrozen =
      static_cast<HBITMAP>(SelectObject(hdcFrozen, g_selectionState->frozenBitmap));
  BitBlt(hdcMem, 0, 0, width, height, hdcFrozen, 0, 0, SRCCOPY);

  // Dim whole screen (WeChat-like dark mask)
  HDC hdcDim = CreateCompatibleDC(hdc);
  HBITMAP hbmDim = CreateCompatibleBitmap(hdc, width, height);
  HBITMAP oldDim = static_cast<HBITMAP>(SelectObject(hdcDim, hbmDim));
  HBRUSH dimBrush = CreateSolidBrush(RGB(0, 0, 0));
  FillRect(hdcDim, &clientRect, dimBrush);
  DeleteObject(dimBrush);
  BLENDFUNCTION blend = {};
  blend.BlendOp = AC_SRC_OVER;
  blend.SourceConstantAlpha = 120;  // ~47% dark
  blend.AlphaFormat = 0;
  AlphaBlend(hdcMem, 0, 0, width, height, hdcDim, 0, 0, width, height, blend);
  SelectObject(hdcDim, oldDim);
  DeleteObject(hbmDim);
  DeleteDC(hdcDim);

  RECT sel = {};
  bool hasSel = false;
  if (g_selectionState->phase == OverlayPhase::Selecting) {
    sel = NormalizedRect(g_selectionState->startPoint,
                         g_selectionState->currentPoint);
    hasSel = (sel.right - sel.left) > 0 && (sel.bottom - sel.top) > 0;
  } else if (g_selectionState->phase == OverlayPhase::Confirmed) {
    sel = g_selectionState->selectedRect;
    hasSel = (sel.right - sel.left) > 0 && (sel.bottom - sel.top) > 0;
  }

  if (hasSel) {
    // Restore clear preview inside selection from frozen bitmap
    BitBlt(hdcMem, sel.left, sel.top, sel.right - sel.left, sel.bottom - sel.top,
           hdcFrozen, sel.left, sel.top, SRCCOPY);
    DrawSelectionChrome(hdcMem, sel,
                        g_selectionState->phase == OverlayPhase::Confirmed);
  }

  SelectObject(hdcFrozen, oldFrozen);
  DeleteDC(hdcFrozen);

  BitBlt(hdc, 0, 0, width, height, hdcMem, 0, 0, SRCCOPY);
  SelectObject(hdcMem, hbmOld);
  DeleteObject(hbmMem);
  DeleteDC(hdcMem);
}

static void FinishOverlay(HWND hwnd, bool cancelled) {
  if (!g_selectionState) return;
  g_selectionState->cancelled = cancelled;
  g_selectionState->finished = !cancelled;
  DestroyWindow(hwnd);
}

static LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wParam,
                                       LPARAM lParam) {
  if (!g_selectionState) return DefWindowProc(hwnd, msg, wParam, lParam);

  switch (msg) {
    case WM_LBUTTONDOWN: {
      const int x = GET_X_LPARAM(lParam);
      const int y = GET_Y_LPARAM(lParam);
      const DWORD now = GetTickCount();

      if (g_selectionState->phase == OverlayPhase::Confirmed) {
        // Double-click inside selection = done (WeChat)
        const bool isDouble =
            (now - g_selectionState->lastClickTick) <= GetDoubleClickTime() &&
            abs(x - g_selectionState->lastClickPt.x) <= 4 &&
            abs(y - g_selectionState->lastClickPt.y) <= 4 &&
            PtInRectInflated(g_selectionState->selectedRect, x, y, 0);
        g_selectionState->lastClickTick = now;
        g_selectionState->lastClickPt = {x, y};
        if (isDouble) {
          FinishOverlay(hwnd, false);
          return 0;
        }

        HitZone hit = HitTestSelection(g_selectionState->selectedRect, x, y);
        if (hit != HitZone::None) {
          g_selectionState->activeHit = hit;
          g_selectionState->dragOrigin = {x, y};
          g_selectionState->dragOriginRect = g_selectionState->selectedRect;
          SetCapture(hwnd);
          return 0;
        }
        // Click outside: start a new selection
        g_selectionState->phase = OverlayPhase::Selecting;
        g_selectionState->startPoint = {x, y};
        g_selectionState->currentPoint = {x, y};
        g_selectionState->activeHit = HitZone::None;
        SetCapture(hwnd);
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }

      g_selectionState->phase = OverlayPhase::Selecting;
      g_selectionState->startPoint = {x, y};
      g_selectionState->currentPoint = {x, y};
      g_selectionState->activeHit = HitZone::None;
      SetCapture(hwnd);
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    }

    case WM_MOUSEMOVE: {
      const int x = GET_X_LPARAM(lParam);
      const int y = GET_Y_LPARAM(lParam);
      if (g_selectionState->phase == OverlayPhase::Selecting &&
          (GetCapture() == hwnd)) {
        g_selectionState->currentPoint = {x, y};
        InvalidateRect(hwnd, nullptr, FALSE);
      } else if (g_selectionState->phase == OverlayPhase::Confirmed &&
                 g_selectionState->activeHit != HitZone::None &&
                 (GetCapture() == hwnd)) {
        const int dx = x - g_selectionState->dragOrigin.x;
        const int dy = y - g_selectionState->dragOrigin.y;
        RECT next = g_selectionState->dragOriginRect;
        ApplyHitDrag(&next, g_selectionState->activeHit, dx, dy,
                     g_selectionState->screenWidth,
                     g_selectionState->screenHeight);
        g_selectionState->selectedRect = next;
        InvalidateRect(hwnd, nullptr, FALSE);
      } else if (g_selectionState->phase == OverlayPhase::Confirmed) {
        HitZone hit = HitTestSelection(g_selectionState->selectedRect, x, y);
        LPCWSTR cursor = IDC_CROSS;
        switch (hit) {
          case HitZone::Move:
            cursor = IDC_SIZEALL;
            break;
          case HitZone::N:
          case HitZone::S:
            cursor = IDC_SIZENS;
            break;
          case HitZone::E:
          case HitZone::W:
            cursor = IDC_SIZEWE;
            break;
          case HitZone::NE:
          case HitZone::SW:
            cursor = IDC_SIZENESW;
            break;
          case HitZone::NW:
          case HitZone::SE:
            cursor = IDC_SIZENWSE;
            break;
          default:
            cursor = IDC_CROSS;
            break;
        }
        SetCursor(LoadCursor(nullptr, cursor));
      }
      return 0;
    }

    case WM_LBUTTONUP: {
      const int x = GET_X_LPARAM(lParam);
      const int y = GET_Y_LPARAM(lParam);
      if (g_selectionState->phase == OverlayPhase::Selecting) {
        ReleaseCapture();
        g_selectionState->currentPoint = {x, y};
        RECT sel = NormalizedRect(g_selectionState->startPoint,
                                  g_selectionState->currentPoint);
        sel = ClampRectToScreen(sel, g_selectionState->screenWidth,
                                g_selectionState->screenHeight);
        if (sel.right - sel.left < kMinSelSize ||
            sel.bottom - sel.top < kMinSelSize) {
          g_selectionState->phase = OverlayPhase::Idle;
          g_selectionState->selectedRect = {};
        } else {
          g_selectionState->selectedRect = sel;
          g_selectionState->phase = OverlayPhase::Confirmed;
          g_selectionState->lastClickTick = GetTickCount();
          g_selectionState->lastClickPt = {x, y};
        }
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }
      if (g_selectionState->activeHit != HitZone::None) {
        ReleaseCapture();
        g_selectionState->activeHit = HitZone::None;
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }

    case WM_LBUTTONDBLCLK: {
      if (g_selectionState->phase == OverlayPhase::Confirmed) {
        const int x = GET_X_LPARAM(lParam);
        const int y = GET_Y_LPARAM(lParam);
        if (PtInRectInflated(g_selectionState->selectedRect, x, y, 0)) {
          FinishOverlay(hwnd, false);
        }
      }
      return 0;
    }

    case WM_KEYDOWN: {
      if (wParam == VK_ESCAPE) {
        FinishOverlay(hwnd, true);
      } else if (wParam == VK_RETURN &&
                 g_selectionState->phase == OverlayPhase::Confirmed) {
        FinishOverlay(hwnd, false);
      }
      return 0;
    }

    case WM_RBUTTONDOWN: {
      FinishOverlay(hwnd, true);
      return 0;
    }

    case WM_ERASEBKGND:
      return 1;

    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd, &ps);
      PaintOverlay(hwnd, hdc);
      EndPaint(hwnd, &ps);
      return 0;
    }

    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }

  return DefWindowProc(hwnd, msg, wParam, lParam);
}

// Temporarily hide the Flutter root window so we don't capture ourselves.
// Always restores in destructor (including cancel / early return).
struct AppWindowHideGuard {
  HWND hwnd = nullptr;
  bool did_hide = false;

  explicit AppWindowHideGuard(HWND app_hwnd) : hwnd(app_hwnd) {
    if (!hwnd || !IsWindow(hwnd)) return;
    if (!IsWindowVisible(hwnd)) return;
    ShowWindow(hwnd, SW_HIDE);
    did_hide = true;
    // Allow DWM/desktop to redraw without our window.
    Sleep(200);
  }

  ~AppWindowHideGuard() { Restore(); }

  void Restore() {
    if (!did_hide || !hwnd || !IsWindow(hwnd)) return;
    did_hide = false;
    ShowWindow(hwnd, SW_SHOW);
    ShowWindow(hwnd, SW_RESTORE);
    SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    SetForegroundWindow(hwnd);
    BringWindowToTop(hwnd);
  }
};

static HWND g_flutter_root_hwnd = nullptr;

// Capture region with interactive overlay
HBITMAP CaptureRegionToBitmap(int* width, int* height, int* x, int* y,
                              bool* cancelled) {
  *cancelled = false;

  SetProcessDPIAware();

  // Hide app first, then freeze virtual desktop (all monitors).
  AppWindowHideGuard hide_guard(g_flutter_root_hwnd);

  const int virtualX = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int virtualY = GetSystemMetrics(SM_YVIRTUALSCREEN);
  int screenWidth = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  int screenHeight = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (screenWidth <= 0 || screenHeight <= 0) {
    screenWidth = GetSystemMetrics(SM_CXSCREEN);
    screenHeight = GetSystemMetrics(SM_CYSCREEN);
  }

  int frozenW = 0;
  int frozenH = 0;
  HBITMAP frozen = CaptureScreenToBitmap(&frozenW, &frozenH, false);
  if (!frozen) {
    *cancelled = true;
    return nullptr;
  }
  if (frozenW > 0) screenWidth = frozenW;
  if (frozenH > 0) screenHeight = frozenH;

  SelectionState state = {};
  state.phase = OverlayPhase::Idle;
  state.cancelled = false;
  state.finished = false;
  state.frozenBitmap = frozen;
  state.screenWidth = screenWidth;
  state.screenHeight = screenHeight;
  g_selectionState = &state;

  const wchar_t* className = L"DunesScreenshotOverlayClass";
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(WNDCLASSEXW);
  wc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
  wc.lpfnWndProc = OverlayWndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hCursor = LoadCursor(nullptr, IDC_CROSS);
  wc.hbrBackground = nullptr;
  wc.lpszClassName = className;

  if (!RegisterClassExW(&wc)) {
    if (GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      DeleteObject(frozen);
      g_selectionState = nullptr;
      return nullptr;
    }
  }

  HWND hwndOverlay = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
      className, L"Screenshot Overlay", WS_POPUP,
      virtualX, virtualY, screenWidth, screenHeight,
      nullptr, nullptr, GetModuleHandle(nullptr), nullptr);

  if (!hwndOverlay) {
    DeleteObject(frozen);
    UnregisterClassW(className, GetModuleHandle(nullptr));
    g_selectionState = nullptr;
    return nullptr;
  }

  ShowWindow(hwndOverlay, SW_SHOW);
  UpdateWindow(hwndOverlay);
  SetForegroundWindow(hwndOverlay);
  SetFocus(hwndOverlay);

  MSG msg;
  while (GetMessage(&msg, nullptr, 0, 0)) {
    TranslateMessage(&msg);
    DispatchMessage(&msg);
  }

  UnregisterClassW(className, GetModuleHandle(nullptr));

  // Restore app window before returning (also runs again in destructor — safe).
  hide_guard.Restore();

  if (state.cancelled || !state.finished) {
    *cancelled = true;
    DeleteObject(frozen);
    g_selectionState = nullptr;
    return nullptr;
  }

  RECT sel = state.selectedRect;
  int selWidth = sel.right - sel.left;
  int selHeight = sel.bottom - sel.top;
  if (selWidth <= 0 || selHeight <= 0) {
    *cancelled = true;
    DeleteObject(frozen);
    g_selectionState = nullptr;
    return nullptr;
  }

  HDC hdcScreen = GetDC(nullptr);
  HDC hdcSrc = CreateCompatibleDC(hdcScreen);
  HDC hdcDst = CreateCompatibleDC(hdcScreen);
  HBITMAP oldSrc = static_cast<HBITMAP>(SelectObject(hdcSrc, frozen));
  HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, selWidth, selHeight);
  if (!hBitmap) {
    SelectObject(hdcSrc, oldSrc);
    DeleteDC(hdcSrc);
    DeleteDC(hdcDst);
    ReleaseDC(nullptr, hdcScreen);
    DeleteObject(frozen);
    g_selectionState = nullptr;
    return nullptr;
  }
  HBITMAP oldDst = static_cast<HBITMAP>(SelectObject(hdcDst, hBitmap));
  BitBlt(hdcDst, 0, 0, selWidth, selHeight, hdcSrc, sel.left, sel.top, SRCCOPY);
  SelectObject(hdcSrc, oldSrc);
  SelectObject(hdcDst, oldDst);
  DeleteDC(hdcSrc);
  DeleteDC(hdcDst);
  ReleaseDC(nullptr, hdcScreen);
  DeleteObject(frozen);

  *width = selWidth;
  *height = selHeight;
  *x = virtualX + sel.left;
  *y = virtualY + sel.top;
  g_selectionState = nullptr;
  return hBitmap;
}

namespace {
constexpr int kScreenshotHotkeyId = 0x4E01;
}

// static
void ScreenshotPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<ScreenshotPlugin>(registrar);

  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.flutter.screenshot",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ScreenshotPlugin::ScreenshotPlugin(flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar) {
  if (registrar_ && registrar_->GetView()) {
    HWND view = registrar_->GetView()->GetNativeWindow();
    g_flutter_root_hwnd = view ? GetAncestor(view, GA_ROOT) : nullptr;
    if (!g_flutter_root_hwnd) g_flutter_root_hwnd = view;
  }

  hotkey_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar_->messenger(), "dev.flutter.screenshot.hotkey",
          &flutter::StandardMethodCodec::GetInstance());

  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam,
             LPARAM lparam) -> std::optional<LRESULT> {
        if (message == WM_HOTKEY &&
            static_cast<int>(wparam) == kScreenshotHotkeyId) {
          NotifyHotkeyPressed();
          return 0;
        }
        return std::nullopt;
      });

  // 热键改由 Dart hotkey_manager 统一注册，避免与插件 RegisterHotKey 双注册冲突。
  // RegisterScreenshotHotkey();
}

ScreenshotPlugin::~ScreenshotPlugin() {
  UnregisterScreenshotHotkey();
  if (registrar_ && window_proc_id_ >= 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
    window_proc_id_ = -1;
  }
}

HWND ScreenshotPlugin::RootWindow() const {
  if (g_flutter_root_hwnd && IsWindow(g_flutter_root_hwnd)) {
    return g_flutter_root_hwnd;
  }
  if (!registrar_ || !registrar_->GetView()) return nullptr;
  HWND view = registrar_->GetView()->GetNativeWindow();
  HWND root = view ? GetAncestor(view, GA_ROOT) : nullptr;
  return root ? root : view;
}

void ScreenshotPlugin::RegisterScreenshotHotkey() {
  HWND hwnd = RootWindow();
  if (!hwnd) return;
  // Ctrl+Alt+A，与微信一致；失败时静默（可能被其它软件占用）。
  hotkey_registered_ = RegisterHotKey(
                           hwnd, kScreenshotHotkeyId,
                           MOD_CONTROL | MOD_ALT | MOD_NOREPEAT,
                           static_cast<UINT>('A')) == TRUE;
}

void ScreenshotPlugin::UnregisterScreenshotHotkey() {
  HWND hwnd = RootWindow();
  if (hwnd && hotkey_registered_) {
    UnregisterHotKey(hwnd, kScreenshotHotkeyId);
  }
  hotkey_registered_ = false;
}

void ScreenshotPlugin::NotifyHotkeyPressed() {
  if (!hotkey_channel_) return;
  hotkey_channel_->InvokeMethod("pressed", nullptr);
}

void ScreenshotPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "triggerSystemSnip") {
    // Simulate Win+Shift+S (Windows 系统截图，支持多屏，无需藏窗)。
    INPUT inputs[6] = {};
    inputs[0].type = INPUT_KEYBOARD;
    inputs[0].ki.wVk = VK_LWIN;
    inputs[1].type = INPUT_KEYBOARD;
    inputs[1].ki.wVk = VK_SHIFT;
    inputs[2].type = INPUT_KEYBOARD;
    inputs[2].ki.wVk = 'S';
    inputs[3].type = INPUT_KEYBOARD;
    inputs[3].ki.wVk = 'S';
    inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
    inputs[4].type = INPUT_KEYBOARD;
    inputs[4].ki.wVk = VK_SHIFT;
    inputs[4].ki.dwFlags = KEYEVENTF_KEYUP;
    inputs[5].type = INPUT_KEYBOARD;
    inputs[5].ki.wVk = VK_LWIN;
    inputs[5].ki.dwFlags = KEYEVENTF_KEYUP;
    const UINT sent = SendInput(ARRAYSIZE(inputs), inputs, sizeof(INPUT));
    result->Success(flutter::EncodableValue(sent == ARRAYSIZE(inputs)));
    return;
  }

  if (method_call.method_name() == "registerHotkey") {
    // 重新解析根窗口（启动早期 GetView 可能尚未就绪）。
    if (registrar_ && registrar_->GetView()) {
      HWND view = registrar_->GetView()->GetNativeWindow();
      g_flutter_root_hwnd = view ? GetAncestor(view, GA_ROOT) : view;
    }
    UnregisterScreenshotHotkey();
    RegisterScreenshotHotkey();
    result->Success(flutter::EncodableValue(hotkey_registered_));
    return;
  }

  if (method_call.method_name().compare("capture") == 0) {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("invalid_argument", "Arguments must be a map");
      return;
    }

    auto mode_it = arguments->find(flutter::EncodableValue("mode"));
    if (mode_it == arguments->end()) {
      result->Error("invalid_argument", "Missing 'mode' parameter");
      return;
    }

    const auto* mode_str = std::get_if<std::string>(&mode_it->second);
    if (!mode_str) {
      result->Error("invalid_argument", "'mode' must be a string");
      return;
    }

    if (*mode_str != "screen" && *mode_str != "region") {
      result->Error("invalid_argument", "Invalid mode: " + *mode_str);
      return;
    }

    bool includeCursor = false;
    auto cursor_it = arguments->find(flutter::EncodableValue("includeCursor"));
    if (cursor_it != arguments->end()) {
      const auto* cursor_bool = std::get_if<bool>(&cursor_it->second);
      if (cursor_bool) includeCursor = *cursor_bool;
    }

    // Refresh root hwnd before capture.
    if (registrar_ && registrar_->GetView()) {
      HWND view = registrar_->GetView()->GetNativeWindow();
      g_flutter_root_hwnd = view ? GetAncestor(view, GA_ROOT) : view;
    }

    if (*mode_str == "screen") {
      int width = 0;
      int height = 0;
      AppWindowHideGuard hide_guard(g_flutter_root_hwnd);
      HBITMAP hBitmap = CaptureScreenToBitmap(&width, &height, includeCursor);
      hide_guard.Restore();
      if (!hBitmap) {
        result->Error("internal_error", "Failed to capture screen",
                      flutter::EncodableValue(static_cast<int>(GetLastError())));
        return;
      }

      std::vector<uint8_t> pngBytes = EncodeBitmapToPNG(hBitmap, width, height);
      DeleteObject(hBitmap);
      if (pngBytes.empty()) {
        result->Error("internal_error", "Failed to encode PNG");
        return;
      }

      flutter::EncodableMap resultMap;
      resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
      resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
      resultMap[flutter::EncodableValue("bytes")] = flutter::EncodableValue(pngBytes);
      result->Success(flutter::EncodableValue(resultMap));
    } else if (*mode_str == "region") {
      int width = 0;
      int height = 0;
      int x = 0;
      int y = 0;
      bool cancelled = false;
      HBITMAP hBitmap =
          CaptureRegionToBitmap(&width, &height, &x, &y, &cancelled);

      if (cancelled || !hBitmap) {
        result->Success();
        return;
      }

      std::vector<uint8_t> pngBytes = EncodeBitmapToPNG(hBitmap, width, height);
      DeleteObject(hBitmap);
      if (pngBytes.empty()) {
        result->Error("internal_error", "Failed to encode PNG");
        return;
      }

      flutter::EncodableMap resultMap;
      resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
      resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
      resultMap[flutter::EncodableValue("bytes")] = flutter::EncodableValue(pngBytes);
      result->Success(flutter::EncodableValue(resultMap));
    } else {
      result->Error("invalid_argument", "Invalid mode: " + *mode_str);
    }
  } else {
    result->NotImplemented();
  }
}

}  // namespace screenshot
