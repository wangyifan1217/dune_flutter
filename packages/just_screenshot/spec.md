先直接幫你把「federated Windows 截圖 plugin」的規格書寫出來，你可以丟給 Copilot 實作。下面會偏向概念＋介面，不會塞太多實作細節（例如 Win32 API 叫什麼），那些你可以之後再跟我要。

---

## 1. 目標與範圍

### 1.1 目標

實作一個 **Flutter federated plugin**，支援在 **Windows 桌面**：

* 截取整個螢幕 (`ScreenshotMode.screen`)
* 讓使用者用滑鼠在螢幕上框出一個矩形區域截圖 (`ScreenshotMode.region`)
* 回傳包含寬高與圖像 bytes 的 `CapturedData`（PNG/ARGB）。

### 1.2 非目標（此版先不做）

* 不支援 macOS / Linux / Web / Mobile（之後可再新增 federated implementation）。
* 不支援「指定視窗截圖」或「自動偵測視窗」。
* 不處理影像壓縮選項，先固定輸出 PNG（或 BGRA/ARGB raw bytes，由你決定）。

---

## 2. 專案結構（Federated Plugin）

建議三個 package：

1. **`screenshot`**

   * 對外公開的 Dart API（你 app 只要依賴這個）。
   * 透過 platform interface 呼叫各平台實作。

2. **`screenshot_platform_interface`**

   * 定義 `ScreenshotPlatform` 抽象類別與共用型別（`CapturedData`, `ScreenshotMode`）。
   * 使用 `plugin_platform_interface` 套件。

3. **`screenshot_windows`**

   * Windows 平台實作（C++/Win32 或 C#/C++/WinRT 任選）。
   * 在 `pubspec.yaml` 宣告 `implements: screenshot`。

目錄大致如下：

```text
screenshot/
  lib/
    screenshot.dart           # 公開 API
    src/
      screenshot_base.dart    # 封裝 ScreenshotPlatform 的封裝類

screenshot_platform_interface/
  lib/
    screenshot_platform_interface.dart   # ScreenshotPlatform 抽象類
    src/
      method_channel_screenshot.dart     # 預設 MethodChannel 實作 (可選)

screenshot_windows/
  lib/
    screenshot_windows.dart   # Windows 註冊 & 實作
  windows/
    screenshot_windows_plugin.cpp  # Win32 實作
```

---

## 3. Dart 公開 API 設計

### 3.1 型別定義

```dart
enum ScreenshotMode {
  /// Drag the cursor around an object to form a rectangle.
  region,

  /// Capture the entire (primary) screen.
  screen,
}

class CapturedData {
  const CapturedData({
    required this.width,
    required this.height,
    required this.bytes,
  });

  /// 圖片寬度（像素）
  final int width;

  /// 圖片高度（像素）
  final int height;

  /// 圖片資料（預設 PNG 或 raw BGRA）
  final Uint8List bytes;
}
```

> 註：你前面變數叫 `ScreenshotData? screenshotData`，class 叫 `CapturedData`，
> 建議統一命名，例如都叫 `CapturedData`，或 `ScreenshotData`，這邊用 `CapturedData` 示範。

---

### 3.2 主要 API

對外只暴露一個單例 / 類別：

```dart
/// 使用方式：
/// final screenshot = Screenshot();
/// final data = await screenshot.capture(mode: ScreenshotMode.region);
class Screenshot {
  Screenshot._internal();

  static final Screenshot _instance = Screenshot._internal();

  factory Screenshot() => _instance;

  /// 截圖
  ///
  /// - [mode] 截圖模式
  /// - [includeCursor] 是否把游標畫進圖片
  /// - [displayId] 目標螢幕（multi-monitor，先可選支援）
  /// - 回傳 null 表示使用者取消（region 模式按 ESC 之類）
  Future<CapturedData?> capture({
    ScreenshotMode mode = ScreenshotMode.region,
    bool includeCursor = false,
    int? displayId,
  }) {
    return ScreenshotPlatform.instance.capture(
      mode: mode,
      includeCursor: includeCursor,
      displayId: displayId,
    );
  }
}
```

---

## 4. Platform Interface 設計

### 4.1 抽象平台類

`screenshot_platform_interface/lib/screenshot_platform_interface.dart`：

```dart
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

enum ScreenshotMode {
  region,
  screen,
}

class CapturedData {
  const CapturedData({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final Uint8List bytes;

  Map<String, Object> toMap() {
    return <String, Object>{
      'width': width,
      'height': height,
      'bytes': bytes,
    };
  }

  static CapturedData fromMap(Map<Object?, Object?> map) {
    return CapturedData(
      width: map['width'] as int,
      height: map['height'] as int,
      bytes: map['bytes'] as Uint8List,
    );
  }
}

abstract class ScreenshotPlatform extends PlatformInterface {
  ScreenshotPlatform() : super(token: _token);

  static final Object _token = Object();

  static ScreenshotPlatform _instance = _DefaultScreenshotPlatform();

  static ScreenshotPlatform get instance => _instance;

  static set instance(ScreenshotPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<CapturedData?> capture({
    required ScreenshotMode mode,
    bool includeCursor = false,
    int? displayId,
  }) {
    throw UnimplementedError('capture() has not been implemented.');
  }
}

/// 預設實作：直接丟 UnimplementedError
class _DefaultScreenshotPlatform extends ScreenshotPlatform {}
```

> 如果你想用 `MethodChannel` 包成一個預設實作，也可以在 `src/method_channel_screenshot.dart` 開一個。

---

### 4.2 MethodChannel 設計（建議）

* Channel 名稱：`"dev.yourname.screenshot"`（自己決定）
* 方法：`"capture"`
* 參數（Map）：

```json
{
  "mode": "region" | "screen",
  "includeCursor": true | false,
  "displayId": 0  // 可選，null 表示 primary
}
```

* 回傳（成功）：

```json
{
  "width": 1920,
  "height": 1080,
  "bytes": <Uint8List PNG bytes>
}
```

* 回傳（使用者取消或失敗）：

```json
null
```

或丟 PlatformException，視你的喜好：

* `code: "cancelled"` → 使用者按 ESC 取消。
* `code: "not_supported"` → 非 Windows 平台等。
* `code: "internal_error"` → 截圖出錯。

---

## 5. Windows 實作規格（行為）

### 5.1 截取整個螢幕 `ScreenshotMode.screen`

行為規格：

1. 以 **primary display** 為主（多螢幕後續可擴充 `displayId`）。
2. 使用 Win32 API：

   * 取得螢幕尺寸（例：`GetSystemMetrics(SM_CXSCREEN)` / `SM_CYSCREEN`）
   * 建立相容 DC + Bitmap
   * 使用 `BitBlt` 把桌面內容拷貝到 Bitmap
   * （選擇性）畫上游標圖案（如果 `includeCursor == true`）
3. 把 Bitmap 轉為：

   * PNG byte array，或
   * raw BGRA 或 ARGB byte array（顏色通道你自己定義）
4. 回傳 `width`, `height`, `bytes`。

### 5.2 區域截圖 `ScreenshotMode.region`

行為規格：

1. 呼叫 `capture(mode: region)` 時，在 **Windows 本機**：

   * 建立一個 **全螢幕透明 overlay** 視窗（最上層）：

     * 半透明暗色遮罩
     * 滑鼠游標變成十字準心
2. 使用者操作流程：

   * 按下左鍵開始：記錄起始點 `(x0, y0)`。
   * 拖曳過程：顯示一個高亮矩形區域（框線或填色），即將截圖範圍。
   * 放開左鍵：記錄終點 `(x1, y1)`，得到 rect。
   * 若使用者按 ESC → 視為取消，關閉 overlay，回傳 `null`（或 throw `PlatformException(code: "cancelled")`）
3. Overlay 關閉後：

   * 依 rect 對螢幕進行部分 `BitBlt` 擷取。
   * 一樣轉為 PNG / BGRA。
4. 回傳 `CapturedData(width, height, bytes)` 到 Dart 端。

### 5.3 Multi-monitor 行為（先訂 spec，可先不實作）

* `displayId == null` → 使用 primary display。
* 之後可新增：

  * `displayId` 對應到 `EnumDisplayMonitors` 出來的第 N 個螢幕。
  * region 模式時 overlay 視窗可以只蓋在指定螢幕。

---

## 6. 取消與錯誤處理

### 6.1 取消

* `ScreenshotMode.region` 中，使用者按下 ESC、右鍵、Alt+F4 任一種：

  * 視為「取消」
  * Dart 端 `capture()` 回傳 `null`。

### 6.2 錯誤

* 若是非 Windows 平台呼叫 Windows 版：

  * `PlatformException(code: "not_supported")`。
* Win32 API 執行失敗：

  * `PlatformException(code: "internal_error", message: "Failed to capture screen")`。
* Dart 端建議把 `PlatformException.code == "cancelled"` 當作正常流程處理（return null）。

---

## 7. Example App 規格

在 `screenshot/example` 中提供簡單測試 UI：

* 兩個按鈕：

  * 「Capture Region」
  * 「Capture Screen」

* 按下後呼叫：

  ```dart
  final screenshot = Screenshot();

  final captured = await screenshot.capture(
    mode: ScreenshotMode.region,
  );
  ```

* 如果 `captured != null`：

  * 用 `Image.memory(captured.bytes)` 顯示。
  * Text 顯示 `width x height`。

* 如果為 `null`：

  * Toast / SnackBar 顯示「已取消」。

---

## 8. 擴充方向（之後可以加）

先寫在 spec 裡讓設計有保留彈性：

* `imageFormat` 參數：`png`, `bmp`, `jpeg`, `rawBgra` 等。
* 指定 Window handle 截圖（用 `FindWindow` 或 `EnumWindows`）。
* 動態錄影（持續 capture，變成 desktop recorder）。
* 支援 macOS / Linux（透過對應的 OS API）。

---

## 9. 使用範例（最終在 app 內長這樣）

```dart
final screenshot = Screenshot();

Future<void> captureRegion() async {
  final CapturedData? data = await screenshot.capture(
    mode: ScreenshotMode.region,
    includeCursor: false,
  );

  if (data == null) {
    // 使用者取消
    return;
  }

  print('Captured: ${data.width} x ${data.height}');
  // 顯示或儲存 data.bytes
}

Future<void> captureFullScreen() async {
  final data = await screenshot.capture(
    mode: ScreenshotMode.screen,
    includeCursor: true,
  );

  if (data == null) return;

  // ...
}
```

---

如果你接下來想要：

* 我幫你把 **三個 package 的骨架 + pubspec + Windows C++ 檔案名稱** 全部生出來
* 或是先改成「region 的矩形選取交互在 Flutter 端用一個 overlay widget 做，Windows 只負責依 rect 截圖」

跟我說你偏好哪一種，我可以直接給你「可編譯骨架專案」。
