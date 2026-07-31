#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutex[] =
    L"Local\\DunesDesktop.B5A14F5D-32E5-484D-BCB1-0156D5F7F5E5";
constexpr wchar_t kFlutterWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

void ActivateExistingWindow() {
  HWND existing_window = FindWindowW(kFlutterWindowClass, nullptr);
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

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance_mutex =
      CreateMutexW(nullptr, FALSE, kSingleInstanceMutex);
  if (single_instance_mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingWindow();
    CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
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

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
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
