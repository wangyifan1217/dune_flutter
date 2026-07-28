#ifndef FLUTTER_PLUGIN_SCREENSHOT_PLUGIN_H_
#define FLUTTER_PLUGIN_SCREENSHOT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace screenshot {

class ScreenshotPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  ScreenshotPlugin(flutter::PluginRegistrarWindows *registrar);

  virtual ~ScreenshotPlugin();

  ScreenshotPlugin(const ScreenshotPlugin&) = delete;
  ScreenshotPlugin& operator=(const ScreenshotPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  void RegisterScreenshotHotkey();
  void UnregisterScreenshotHotkey();
  void NotifyHotkeyPressed();
  HWND RootWindow() const;

  flutter::PluginRegistrarWindows *registrar_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> hotkey_channel_;
  int window_proc_id_ = -1;
  bool hotkey_registered_ = false;
};

}  // namespace screenshot

#endif  // FLUTTER_PLUGIN_SCREENSHOT_PLUGIN_H_
