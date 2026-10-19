#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutex[] =
    L"Local\\DunesDesktop.B5A14F5D-32E5-484D-BCB1-0156D5F7F5E5";
constexpr wchar_t kFlutterWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

void ActivateExistingWindow(HWND existing_window) {
  if (existing_window == nullptr) {
    return;
  }

  if (IsIconic(existing_window)) {
    ShowWindowAsync(existing_window, SW_RESTORE);
  } else {
    ShowWindowAsync(existing_window, SW_SHOW);
  }
  SetForegroundWindow(existing_window);
}

bool WindowIsResponsive(HWND hwnd) {
  if (hwnd == nullptr || !IsWindow(hwnd)) {
    return false;
  }
  // 只用系统的挂起判断。短超时会把正在启动、消息循环暂时没空的正常进程误杀。
  return !IsHungAppWindow(hwnd);
}

// 覆盖安装后旧进程可能停在白屏上仍占着互斥量。把它结束后由本次启动接管。
bool TerminateProcessForWindow(HWND hwnd) {
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == 0 || pid == GetCurrentProcessId()) {
    return false;
  }
  HANDLE process = OpenProcess(SYNCHRONIZE | PROCESS_TERMINATE, FALSE, pid);
  if (process == nullptr) {
    return false;
  }
  if (!TerminateProcess(process, 1)) {
    CloseHandle(process);
    return false;
  }
  const DWORD wait = WaitForSingleObject(process, 3000);
  CloseHandle(process);
  return wait == WAIT_OBJECT_0;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance_mutex =
      CreateMutexW(nullptr, FALSE, kSingleInstanceMutex);
  if (single_instance_mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing_window = FindWindowW(kFlutterWindowClass, nullptr);
    const bool took_over_hung_window =
        existing_window != nullptr &&
        !WindowIsResponsive(existing_window) &&
        TerminateProcessForWindow(existing_window);
    if (!took_over_hung_window) {
      ActivateExistingWindow(existing_window);
      CloseHandle(single_instance_mutex);
      return EXIT_SUCCESS;
    }
    // 旧窗口已无响应并被结束。当前进程持有互斥量，继续创建新窗口。
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  // 核显优先。独显（常见于 NVIDIA 双显卡笔记本）上 ANGLE 交画面会失败，
  // 窗口一直白屏，随后驱动超时把进程打崩。只有独显的机器会自动退回那块显卡。
  project.set_gpu_preference(flutter::GpuPreference::LowPowerPreference);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // 必须与 chat_layout.dart 的 kDesktopWindowDefaultSize 一致。
  // 首帧后再改尺寸会拆掉 Flutter 表面，覆盖安装后表现为整窗白屏。
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1080, 720);
  if (!window.Create(L"dunes_app", origin, size)) {
    return EXIT_FAILURE;
  }
  // Close-to-tray requires QuitOnClose=false, otherwise hide still quits.
  window.SetQuitOnClose(false);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance_mutex != nullptr) {
    CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
