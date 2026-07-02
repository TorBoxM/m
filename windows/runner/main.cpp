#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <bitsdojo_window_windows/bitsdojo_window_plugin.h>
auto bdw = bitsdojo_window_configure(BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP);
#include "flutter_window.h"
#include "utils.h"

// Windows application entry point
int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach console for debug output
  #ifdef _DEBUG
  if (!::AttachConsole(ATTACH_PARENT_PROCESS)) {
    CreateAndAttachConsole();
  }
  #else
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }
  #endif

  // Initialize COM
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Initialize Flutter project
  flutter::DartProject project(L"data");
  
  // Performance optimization: basic GC optimization configuration
  std::vector<std::string> dart_args = {
    "--concurrent_gc",      // Enable concurrent garbage collection
    "--use_compactor"       // Enable memory compactor
  };
  
  // Merge user command line arguments
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  dart_args.insert(dart_args.end(), command_line_arguments.begin(), command_line_arguments.end());
  
  project.set_dart_entrypoint_arguments(std::move(dart_args));

  // Create Flutter window
  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(900, 660);
  
  if (!window.Create(L"TorBox", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Run message loop
  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}