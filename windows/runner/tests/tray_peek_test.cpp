// Standalone Windows smoke test: includes the production popup implementation.
// Link with flutter_wrapper_app, flutter_windows, gdiplus, ole32, shell32,
// user32 and gdi32. Optional first argument saves a rendered PNG preview.
#include "../tray_peek.cpp"
#include <cassert>
#include <iostream>

void ClickAt(int x, int y) {
  SendMessageW(g_hwnd, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(x, y));
  SendMessageW(g_hwnd, WM_LBUTTONUP, 0, MAKELPARAM(x, y));
}

void SavePreview(const wchar_t* path) {
  UpdateWindow(g_hwnd);
  RECT rc{};
  GetClientRect(g_hwnd, &rc);
  HDC source = GetDC(g_hwnd);
  HDC target = CreateCompatibleDC(source);
  HBITMAP image = CreateCompatibleBitmap(source, rc.right, rc.bottom);
  HGDIOBJ previous = SelectObject(target, image);
  BitBlt(target, 0, 0, rc.right, rc.bottom, source, 0, 0, SRCCOPY);
  UINT count = 0, bytes = 0;
  Gdiplus::GetImageEncodersSize(&count, &bytes);
  std::vector<uint8_t> buffer(bytes);
  auto* encoders = reinterpret_cast<Gdiplus::ImageCodecInfo*>(buffer.data());
  Gdiplus::GetImageEncoders(count, bytes, encoders);
  bool saved = false;
  {
    Gdiplus::Bitmap bitmap(image, nullptr);
    for (UINT i = 0; i < count; ++i) {
      if (wcscmp(encoders[i].MimeType, L"image/png") == 0) {
        saved = bitmap.Save(path, &encoders[i].Clsid) == Gdiplus::Ok;
        break;
      }
    }
  }
  SelectObject(target, previous);
  DeleteObject(image);
  DeleteDC(target);
  ReleaseDC(g_hwnd, source);
  assert(saved);
}

int wmain(int argc, wchar_t* argv[]) {
  EnsureGdiplus();
  for (int i = 0; i < 3; ++i) {
    PeekItem item;
    item.id = i + 1;
    item.title = i == 0 ? L"王奕凡" : i == 1 ? L"产品研发协作群" : L"财务对账群";
    item.preview = i == 0 ? L"[@我] 请确认本月付款明细" : i == 1 ? L"李明：新版审批列表已更新" : L"[文件] 十月份对账明细.xlsx";
    item.initial = i == 0 ? L"奕" : i == 1 ? L"产" : L"财";
    item.unread = i == 0 ? 3 : i == 1 ? 1 : 120;
    g_items.push_back(std::move(item));
  }
  g_total = 124;
  g_flashing = true;
  for (const int dpi : {96, 144, 192}) {
    g_dpi = dpi;
    assert(HitRow(-1) == -1);
    assert(HitRow(0) == -1);
    assert(HitRow(HeaderH() - 1) == -1);
    assert(HitRow(HeaderH()) == 0);
    assert(HitRow(HeaderH() + RowH()) == 1);
    assert(HitRow(HeaderH() + RowCount() * RowH()) == -1);
    assert(HitTarget(-1, HeaderH(), Width(), ContentHeight()) == -1);
    assert(HitTarget(Width(), HeaderH(), Width(), ContentHeight()) == -1);
    assert(HitTarget(Width() - Pad(), ContentHeight(), Width(), ContentHeight()) == -1);
    assert(HitTarget(Pad(), ContentHeight() - 1, Width(), ContentHeight()) == -1);
    assert(HitTarget(Width() - Pad(), ContentHeight() - 1, Width(), ContentHeight()) == -2);
  }
  ShowPeek();
  assert(IsWindowVisible(g_hwnd));
  assert(SendMessageW(g_hwnd, WM_MOUSEACTIVATE, 0, 0) == MA_NOACTIVATE);
  const int x = Pad() + Avatar() + Dip(8);
  const int first = HeaderH() + RowH() / 2;
  const int second = first + RowH();
  SendMessageW(g_hwnd, WM_MOUSEMOVE, 0, MAKELPARAM(x, Dip(10)));
  assert(g_hot == -1);
  ClickAt(x, Dip(10));
  assert(IsWindowVisible(g_hwnd));
  SendMessageW(g_hwnd, WM_LBUTTONUP, 0, MAKELPARAM(x, first));
  assert(IsWindowVisible(g_hwnd));
  SendMessageW(g_hwnd, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(x, first));
  SendMessageW(g_hwnd, WM_LBUTTONUP, 0, MAKELPARAM(x, second));
  assert(IsWindowVisible(g_hwnd));
  ClickAt(x, first);
  assert(!IsWindowVisible(g_hwnd));
  ShowPeek();
  ClickAt(Width() - Pad(), ContentHeight() - Dip(12));
  assert(!g_flashing && IsWindowVisible(g_hwnd));
  assert(HitTarget(Width() - Pad(), ContentHeight() - Dip(12), Width(), ContentHeight()) == -1);
  g_flashing = true;
  SendMessageW(g_hwnd, WM_MOUSEMOVE, 0, MAKELPARAM(x, second));
  assert(g_hot == 1);
  if (argc > 1) SavePreview(argv[1]);
  SendMessageW(g_hwnd, WM_MOUSELEAVE, 0, 0);
  assert(g_hot == -1);
  const flutter::EncodableValue empty(flutter::EncodableList{});
  UpdateItems(&empty);
  assert(!IsWindowVisible(g_hwnd));
  HidePeek(true);
  assert(GetCapture() != g_hwnd);
  TrayPeekShutdown();
  std::cout << "PASS: DPI hit bounds, header, hover, press/release, drag, footer, capture cleanup.\n";
  return 0;
}
