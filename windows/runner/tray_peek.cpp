#include "tray_peek.h"

#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <objidl.h>
#include <gdiplus.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

namespace {

constexpr wchar_t kClassName[] = L"DunesTrayPeek";
constexpr int kMaxRows = 6;
constexpr UINT kHideTimer = 41;

struct PeekItem {
  int64_t id = 0;
  std::wstring title;
  std::wstring preview;
  int unread = 0;
  std::wstring initial;
  COLORREF color = RGB(123, 92, 216);
  std::unique_ptr<Gdiplus::Bitmap> avatar;
};

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
HWND g_hwnd = nullptr;
std::vector<PeekItem> g_items;
std::wstring g_title = L"沙丘";
int g_total = 0;
bool g_flashing = false;
int g_hot = -1;  // row index, or -2 footer
bool g_class_reg = false;
int g_dpi = 96;
ULONG_PTR g_gdiplus_token = 0;

bool EnsureGdiplus() {
  if (g_gdiplus_token != 0) return true;
  Gdiplus::GdiplusStartupInput input;
  const Gdiplus::Status st =
      Gdiplus::GdiplusStartup(&g_gdiplus_token, &input, nullptr);
  if (st != Gdiplus::Ok) {
    g_gdiplus_token = 0;
    return false;
  }
  return true;
}

void ShutdownGdiplus() {
  g_items.clear();
  if (g_gdiplus_token == 0) return;
  Gdiplus::GdiplusShutdown(g_gdiplus_token);
  g_gdiplus_token = 0;
}

void AddRoundRect(Gdiplus::GraphicsPath* path, int x, int y, int w, int h,
                  int r) {
  if (!path) return;
  if (r <= 0) {
    path->AddRectangle(Gdiplus::Rect(x, y, w, h));
    return;
  }
  const int d = r * 2;
  path->AddArc(x, y, d, d, 180.0f, 90.0f);
  path->AddArc(x + w - d, y, d, d, 270.0f, 90.0f);
  path->AddArc(x + w - d, y + h - d, d, d, 0.0f, 90.0f);
  path->AddArc(x, y + h - d, d, d, 90.0f, 90.0f);
  path->CloseFigure();
}

std::unique_ptr<Gdiplus::Bitmap> BitmapFromPng(
    const std::vector<uint8_t>& bytes) {
  if (bytes.empty() || !EnsureGdiplus()) return nullptr;
  HGLOBAL mem = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  if (!mem) return nullptr;
  void* locked = GlobalLock(mem);
  if (!locked) {
    GlobalFree(mem);
    return nullptr;
  }
  std::memcpy(locked, bytes.data(), bytes.size());
  GlobalUnlock(mem);
  IStream* stream = nullptr;
  if (FAILED(CreateStreamOnHGlobal(mem, TRUE, &stream)) || !stream) {
    GlobalFree(mem);
    return nullptr;
  }
  std::unique_ptr<Gdiplus::Bitmap> src(Gdiplus::Bitmap::FromStream(stream));
  if (!src || src->GetLastStatus() != Gdiplus::Ok) {
    stream->Release();
    return nullptr;
  }
  const UINT w = src->GetWidth();
  const UINT h = src->GetHeight();
  if (w == 0 || h == 0) {
    stream->Release();
    return nullptr;
  }
  std::unique_ptr<Gdiplus::Bitmap> clone(src->Clone(
      0, 0, static_cast<INT>(w), static_cast<INT>(h), PixelFormat32bppPARGB));
  stream->Release();
  if (!clone || clone->GetLastStatus() != Gdiplus::Ok) return src;
  return clone;
}

void DrawAvatarImage(HDC hdc, Gdiplus::Bitmap* bmp, int x, int y, int size,
                     int radius) {
  if (!hdc || !bmp) return;
  Gdiplus::Graphics g(hdc);
  g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
  g.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);
  Gdiplus::GraphicsPath path;
  AddRoundRect(&path, x, y, size, size, radius);
  g.SetClip(&path);
  g.DrawImage(bmp, x, y, size, size);
}

int Dip(int v) { return MulDiv(v, g_dpi, 96); }
int Width() { return Dip(248); }
int Pad() { return Dip(10); }
int HeaderH() { return Dip(28); }
int RowH() { return Dip(44); }
int FooterH() { return g_flashing ? Dip(32) : 0; }
int Avatar() { return Dip(28); }

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  if (len <= 0) return std::wstring();
  std::wstring out(static_cast<size_t>(len), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, out.data(), len);
  if (!out.empty() && out.back() == L'\0') out.pop_back();
  return out;
}

COLORREF ArgbToColor(int64_t argb) {
  const int r = static_cast<int>((argb >> 16) & 0xFF);
  const int g = static_cast<int>((argb >> 8) & 0xFF);
  const int b = static_cast<int>(argb & 0xFF);
  return RGB(r, g, b);
}

void RefreshDpi() {
  g_dpi = 96;
  if (!g_hwnd) return;
  using GetDpiForWindowFn = UINT(WINAPI*)(HWND);
  HMODULE user32 = GetModuleHandleW(L"user32.dll");
  if (!user32) return;
  auto getDpi = reinterpret_cast<GetDpiForWindowFn>(
      GetProcAddress(user32, "GetDpiForWindow"));
  if (!getDpi) return;
  const UINT dpi = getDpi(g_hwnd);
  if (dpi != 0) g_dpi = static_cast<int>(dpi);
}

int RowCount() {
  return static_cast<int>(
      std::min<size_t>(g_items.size(), static_cast<size_t>(kMaxRows)));
}

int ContentHeight() {
  const int n = RowCount();
  if (n <= 0) return Dip(40);
  return HeaderH() + n * RowH() + FooterH();
}

void TrackLeave(HWND hwnd);
bool GetTrayIconRect(RECT* out);
bool CursorShouldKeepPeek();
void HidePeek(bool force);
void ScheduleHide();

void TrackLeave(HWND hwnd) {
  TRACKMOUSEEVENT tme{};
  tme.cbSize = sizeof(tme);
  tme.dwFlags = TME_LEAVE;
  tme.hwndTrack = hwnd;
  TrackMouseEvent(&tme);
}

bool GetTrayIconRect(RECT* out) {
  if (!out) return false;
  HWND main = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", nullptr);
  if (!main) return false;
  NOTIFYICONIDENTIFIER id{};
  id.cbSize = sizeof(id);
  id.hWnd = main;
  id.uID = 1;
  return SUCCEEDED(Shell_NotifyIconGetRect(&id, out));
}

bool CursorShouldKeepPeek() {
  POINT pt;
  GetCursorPos(&pt);
  if (g_hwnd && IsWindowVisible(g_hwnd)) {
    RECT rc;
    GetWindowRect(g_hwnd, &rc);
    InflateRect(&rc, 4, 4);
    if (PtInRect(&rc, pt)) return true;
  }
  RECT icon{};
  if (!GetTrayIconRect(&icon)) return false;
  InflateRect(&icon, 12, 12);
  return PtInRect(&icon, pt) != FALSE;
}

void HidePeek(bool force) {
  if (!force && CursorShouldKeepPeek()) {
    ScheduleHide();
    return;
  }
  if (g_hwnd) {
    KillTimer(g_hwnd, kHideTimer);
    if (IsWindowVisible(g_hwnd)) {
      ShowWindow(g_hwnd, SW_HIDE);
    }
  }
  g_hot = -1;
}

void ScheduleHide() {
  if (!g_hwnd) return;
  SetTimer(g_hwnd, kHideTimer, 280, nullptr);
}

void NotifyOpen(int64_t id) {
  HidePeek(true);
  if (!g_channel) return;
  g_channel->InvokeMethod(
      "open", std::make_unique<flutter::EncodableValue>(id));
}

void NotifyCancelFlash() {
  if (!g_channel) return;
  g_flashing = false;
  g_channel->InvokeMethod(
      "cancelFlash", std::make_unique<flutter::EncodableValue>());
  if (g_hwnd && IsWindowVisible(g_hwnd)) {
    InvalidateRect(g_hwnd, nullptr, FALSE);
  }
}

HFONT MakeFont(int dip_size, int weight) {
  return CreateFontW(-Dip(dip_size), 0, 0, 0, weight, FALSE, FALSE, FALSE,
                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
                     L"Microsoft YaHei UI");
}

void DrawPreview(HDC mem, const std::wstring& preview, RECT rc) {
  const std::wstring text = preview.empty() ? L"有未读消息" : preview;
  size_t mention = 0;
  if (text.size() >= 2 && text[0] == L'[' && text[1] == L'@') {
    const auto pos = text.find(L']');
    if (pos != std::wstring::npos) mention = pos + 1;
  } else if (!text.empty() && text[0] == L'@') {
    const auto pos = text.find(L' ');
    mention = pos == std::wstring::npos ? text.size() : pos;
  }
  if (mention == 0) {
    SetTextColor(mem, RGB(136, 136, 136));
    DrawTextW(mem, text.c_str(), -1, &rc,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    return;
  }
  SIZE sz{};
  GetTextExtentPoint32W(mem, text.c_str(), static_cast<int>(mention), &sz);
  RECT mrc = rc;
  mrc.right = (std::min)(rc.left + static_cast<int>(sz.cx), rc.right);
  SetTextColor(mem, RGB(250, 81, 81));
  DrawTextW(mem, text.c_str(), static_cast<int>(mention), &mrc,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  RECT rest = rc;
  rest.left = mrc.right;
  if (rest.left < rest.right) {
    SetTextColor(mem, RGB(136, 136, 136));
    DrawTextW(mem, text.c_str() + mention, -1, &rest,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
  }
}

void Paint(HWND hwnd) {
  PAINTSTRUCT ps;
  HDC hdc = BeginPaint(hwnd, &ps);
  RECT rc;
  GetClientRect(hwnd, &rc);

  HDC mem = CreateCompatibleDC(hdc);
  HBITMAP bmp = CreateCompatibleBitmap(hdc, rc.right, rc.bottom);
  HGDIOBJ old_bmp = SelectObject(mem, bmp);

  HBRUSH bg = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(mem, &rc, bg);
  DeleteObject(bg);

  HFONT header_font = MakeFont(12, FW_NORMAL);
  HFONT title_font = MakeFont(13, FW_SEMIBOLD);
  HFONT body_font = MakeFont(12, FW_NORMAL);
  HFONT av_font = MakeFont(12, FW_SEMIBOLD);

  SetBkMode(mem, TRANSPARENT);
  const int rows = RowCount();
  const int pad = Pad();
  const int header_h = HeaderH();
  const int row_h = RowH();
  const int av = Avatar();

  SelectObject(mem, header_font);
  SetTextColor(mem, RGB(136, 136, 136));
  wchar_t header[64];
  const int total = g_total > 0 ? g_total : rows;
  wsprintfW(header, L"%s · %d", g_title.c_str(), total);
  RECT header_rc = {pad, 0, rc.right - pad, header_h};
  DrawTextW(mem, header, -1, &header_rc,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

  for (int i = 0; i < rows; ++i) {
    const PeekItem& it = g_items[static_cast<size_t>(i)];
    RECT row = {0, header_h + i * row_h, rc.right, header_h + (i + 1) * row_h};
    if (i == g_hot) {
      HBRUSH hot = CreateSolidBrush(RGB(246, 247, 250));
      FillRect(mem, &row, hot);
      DeleteObject(hot);
    }
    const int cy = row.top + row_h / 2;
    const int ax = pad;
    const int ay = cy - av / 2;
    const int rr = (std::max)(2, av * 18 / 100);
    RECT avrc = {ax, ay, ax + av, ay + av};
    if (it.avatar) {
      DrawAvatarImage(mem, it.avatar.get(), ax, ay, av, rr);
    } else {
      HBRUSH brush = CreateSolidBrush(it.color);
      HGDIOBJ old_br = SelectObject(mem, brush);
      HGDIOBJ old_pen = SelectObject(mem, GetStockObject(NULL_PEN));
      RoundRect(mem, ax, ay, ax + av, ay + av, rr, rr);
      SelectObject(mem, old_br);
      SelectObject(mem, old_pen);
      DeleteObject(brush);

      SelectObject(mem, av_font);
      SetTextColor(mem, RGB(255, 255, 255));
      DrawTextW(mem, it.initial.c_str(), -1, &avrc,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    }

    const int text_left = ax + av + Dip(8);
    const int text_right = rc.right - Dip(28);
    SelectObject(mem, title_font);
    SetTextColor(mem, RGB(25, 25, 25));
    RECT name = {text_left, row.top + Dip(4), text_right, row.top + Dip(22)};
    DrawTextW(mem, it.title.c_str(), -1, &name,
              DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    SelectObject(mem, body_font);
    RECT preview = {text_left, row.top + Dip(22), text_right, row.bottom - Dip(4)};
    DrawPreview(mem, it.preview, preview);

    const int dot = Dip(8);
    const int dx = rc.right - pad - dot;
    const int dy = cy - dot / 2;
    HBRUSH red = CreateSolidBrush(RGB(250, 81, 81));
    HGDIOBJ obr = SelectObject(mem, red);
    HGDIOBJ open = SelectObject(mem, GetStockObject(NULL_PEN));
    Ellipse(mem, dx, dy, dx + dot, dy + dot);
    SelectObject(mem, obr);
    SelectObject(mem, open);
    DeleteObject(red);
  }

  if (g_flashing) {
    RECT footer = {0, rc.bottom - FooterH(), rc.right, rc.bottom};
    if (g_hot == -2) {
      HBRUSH hot = CreateSolidBrush(RGB(246, 247, 250));
      FillRect(mem, &footer, hot);
      DeleteObject(hot);
    }
    SelectObject(mem, body_font);
    SetTextColor(mem, RGB(87, 107, 149));
    RECT link = {pad, footer.top, rc.right - pad, footer.bottom};
    DrawTextW(mem, L"取消闪烁", -1, &link,
              DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
  }

  HPEN border = CreatePen(PS_SOLID, 1, RGB(228, 230, 235));
  HGDIOBJ old_pen = SelectObject(mem, border);
  HGDIOBJ old_br = SelectObject(mem, GetStockObject(NULL_BRUSH));
  const int cr = Dip(8);
  RoundRect(mem, 0, 0, rc.right - 1, rc.bottom - 1, cr, cr);
  SelectObject(mem, old_pen);
  SelectObject(mem, old_br);
  DeleteObject(border);

  BitBlt(hdc, 0, 0, rc.right, rc.bottom, mem, 0, 0, SRCCOPY);
  SelectObject(mem, old_bmp);
  DeleteObject(bmp);
  DeleteDC(mem);
  DeleteObject(header_font);
  DeleteObject(title_font);
  DeleteObject(body_font);
  DeleteObject(av_font);
  EndPaint(hwnd, &ps);
}

int HitRow(int y) {
  const int rows = RowCount();
  if (rows <= 0) return -1;
  const int idx = (y - HeaderH()) / RowH();
  if (idx < 0 || idx >= rows) return -1;
  return idx;
}

bool HitFooter(int y, int height) {
  if (!g_flashing) return false;
  return y >= height - FooterH();
}

void PlaceWindow() {
  RefreshDpi();
  const int w = Width();
  const int h = ContentHeight();
  RECT icon{};
  POINT anchor{};
  if (GetTrayIconRect(&icon)) {
    anchor.x = (icon.left + icon.right) / 2;
    anchor.y = (icon.top + icon.bottom) / 2;
  } else {
    GetCursorPos(&anchor);
    icon = {anchor.x - 12, anchor.y - 12, anchor.x + 12, anchor.y + 12};
  }
  int x = anchor.x - w / 2;
  int y = icon.top - h - Dip(8);
  HMONITOR mon = MonitorFromRect(&icon, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi{sizeof(mi)};
  if (GetMonitorInfoW(mon, &mi)) {
    const RECT& work = mi.rcWork;
    x = (std::max)(static_cast<int>(work.left + 8),
                   (std::min)(x, static_cast<int>(work.right - w - 8)));
    if (y < work.top + 8) {
      y = icon.bottom + Dip(8);
    }
    if (y + h > work.bottom - 8) {
      y = (std::max)(static_cast<int>(work.top + 8),
                     static_cast<int>(work.bottom - h - 8));
    }
  }
  SetWindowPos(g_hwnd, HWND_TOPMOST, x, y, w, h,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  HRGN rgn = CreateRoundRectRgn(0, 0, w + 1, h + 1, Dip(8), Dip(8));
  SetWindowRgn(g_hwnd, rgn, TRUE);
}

LRESULT CALLBACK PeekProc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
  switch (msg) {
    case WM_MOUSEMOVE: {
      KillTimer(hwnd, kHideTimer);
      TrackLeave(hwnd);
      RECT rc;
      GetClientRect(hwnd, &rc);
      const int y = GET_Y_LPARAM(lparam);
      const int next = HitFooter(y, rc.bottom) ? -2 : HitRow(y);
      if (next != g_hot) {
        g_hot = next;
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      ScheduleHide();
      return 0;
    case WM_LBUTTONUP: {
      RECT rc;
      GetClientRect(hwnd, &rc);
      const int y = GET_Y_LPARAM(lparam);
      if (HitFooter(y, rc.bottom)) {
        NotifyCancelFlash();
        PlaceWindow();
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }
      const int row = HitRow(y);
      if (row >= 0 && static_cast<size_t>(row) < g_items.size()) {
        NotifyOpen(g_items[static_cast<size_t>(row)].id);
      }
      return 0;
    }
    case WM_TIMER:
      if (wparam == kHideTimer) HidePeek(false);
      return 0;
    case WM_PAINT:
      Paint(hwnd);
      return 0;
    case WM_ERASEBKGND:
      return 1;
    default:
      break;
  }
  return DefWindowProcW(hwnd, msg, wparam, lparam);
}

void EnsureWindow() {
  if (g_hwnd) return;
  HINSTANCE inst = GetModuleHandleW(nullptr);
  if (!g_class_reg) {
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_DROPSHADOW;
    wc.lpfnWndProc = PeekProc;
    wc.hInstance = inst;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = kClassName;
    RegisterClassExW(&wc);
    g_class_reg = true;
  }
  g_hwnd = CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE, kClassName, L"",
      WS_POPUP, 0, 0, Width(), Dip(40), nullptr, nullptr, inst, nullptr);
}

void ShowPeek() {
  if (g_items.empty()) {
    HidePeek(true);
    return;
  }
  EnsureWindow();
  if (!g_hwnd) return;
  KillTimer(g_hwnd, kHideTimer);
  PlaceWindow();
  InvalidateRect(g_hwnd, nullptr, FALSE);
  TrackLeave(g_hwnd);
}

const flutter::EncodableValue* MapGet(const flutter::EncodableMap& map,
                                      const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return nullptr;
  return &it->second;
}

int64_t AsInt(const flutter::EncodableValue* v) {
  if (!v) return 0;
  if (std::holds_alternative<int32_t>(*v)) return std::get<int32_t>(*v);
  if (std::holds_alternative<int64_t>(*v)) return std::get<int64_t>(*v);
  if (std::holds_alternative<bool>(*v)) return std::get<bool>(*v) ? 1 : 0;
  return 0;
}

const std::vector<uint8_t>* AsBytes(const flutter::EncodableValue* v) {
  if (!v) return nullptr;
  if (std::holds_alternative<std::vector<uint8_t>>(*v)) {
    return &std::get<std::vector<uint8_t>>(*v);
  }
  return nullptr;
}

void ParseItem(const flutter::EncodableMap& map, PeekItem* item) {
  item->id = AsInt(MapGet(map, "id"));
  if (const auto* v = MapGet(map, "title");
      v && std::holds_alternative<std::string>(*v)) {
    item->title = Utf8ToWide(std::get<std::string>(*v));
  }
  if (const auto* v = MapGet(map, "preview");
      v && std::holds_alternative<std::string>(*v)) {
    item->preview = Utf8ToWide(std::get<std::string>(*v));
  }
  item->unread = static_cast<int>(AsInt(MapGet(map, "unread")));
  if (const auto* v = MapGet(map, "initial");
      v && std::holds_alternative<std::string>(*v)) {
    item->initial = Utf8ToWide(std::get<std::string>(*v));
    if (item->initial.size() > 1) item->initial.resize(1);
  }
  if (const auto* v = MapGet(map, "color")) {
    item->color = ArgbToColor(AsInt(v));
  }
  if (const auto* bytes = AsBytes(MapGet(map, "avatarPng"))) {
    item->avatar = BitmapFromPng(*bytes);
  }
  if (item->initial.empty()) item->initial = L"?";
  if (item->unread < 1) item->unread = 1;
}

void UpdateFromList(const flutter::EncodableList& list) {
  g_items.clear();
  for (const auto& raw : list) {
    if (!std::holds_alternative<flutter::EncodableMap>(raw)) continue;
    PeekItem item;
    ParseItem(std::get<flutter::EncodableMap>(raw), &item);
    g_items.push_back(std::move(item));
    if (g_items.size() >= static_cast<size_t>(kMaxRows)) break;
  }
}

void UpdateItems(const flutter::EncodableValue* args) {
  g_items.clear();
  g_total = 0;
  g_flashing = false;
  if (args == nullptr) return;
  if (std::holds_alternative<flutter::EncodableList>(*args)) {
    UpdateFromList(std::get<flutter::EncodableList>(*args));
    g_total = static_cast<int>(g_items.size());
  } else if (std::holds_alternative<flutter::EncodableMap>(*args)) {
    const auto& map = std::get<flutter::EncodableMap>(*args);
    if (const auto* v = MapGet(map, "title");
        v && std::holds_alternative<std::string>(*v)) {
      const auto title = Utf8ToWide(std::get<std::string>(*v));
      if (!title.empty()) g_title = title;
    }
    g_total = static_cast<int>(AsInt(MapGet(map, "total")));
    g_flashing = AsInt(MapGet(map, "flashing")) != 0;
    if (const auto* v = MapGet(map, "items");
        v && std::holds_alternative<flutter::EncodableList>(*v)) {
      UpdateFromList(std::get<flutter::EncodableList>(*v));
    }
  }
  if (g_total < static_cast<int>(g_items.size())) {
    g_total = static_cast<int>(g_items.size());
  }
  if (g_hwnd && IsWindowVisible(g_hwnd)) {
    if (g_items.empty()) {
      HidePeek(true);
    } else {
      PlaceWindow();
      InvalidateRect(g_hwnd, nullptr, FALSE);
    }
  }
}

}  // namespace

void RegisterTrayPeekChannel(flutter::BinaryMessenger* messenger) {
  if (!messenger) return;
  EnsureGdiplus();
  g_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "nova.dunes/tray_peek",
          &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "update") {
          UpdateItems(call.arguments());
          result->Success();
          return;
        }
        if (call.method_name() == "show") {
          ShowPeek();
          result->Success();
          return;
        }
        if (call.method_name() == "hide") {
          HidePeek(true);
          result->Success();
          return;
        }
        if (call.method_name() == "scheduleHide") {
          ScheduleHide();
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

void TrayPeekShutdown() {
  HidePeek(true);
  if (g_hwnd) {
    DestroyWindow(g_hwnd);
    g_hwnd = nullptr;
  }
  g_channel.reset();
  ShutdownGdiplus();
}
