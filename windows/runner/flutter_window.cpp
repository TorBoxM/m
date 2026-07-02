// UTF-8 BOM
#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <optional>

#include <windows.h>
#include <wininet.h>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // 创建 Flutter 视图控制器
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left,
      frame.bottom - frame.top,
      project_);
  
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  
  // 注册 Flutter 插件
  RegisterPlugins(flutter_controller_->engine());

  session_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "io.github.TorBox/session",
      &flutter::StandardMethodCodec::GetInstance());
  session_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleSessionMethodCall(call, std::move(result));
  });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (session_channel_) {
    session_channel_->SetMethodCallHandler(nullptr);
  }
  session_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleSessionMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() != "setSystemProxyOwnership") {
    result->NotImplemented();
    return;
  }

  const auto* arguments = call.arguments();
  if (!arguments || !std::holds_alternative<bool>(*arguments)) {
    result->Error("invalid_arguments", "Expected a boolean argument.");
    return;
  }

  should_disable_system_proxy_on_session_end_ = std::get<bool>(*arguments);
  result->Success();
}

void FlutterWindow::DisableSystemProxyForSessionEnd() {
  if (!should_disable_system_proxy_on_session_end_) {
    return;
  }

  INTERNET_PER_CONN_OPTIONW option{};
  option.dwOption = INTERNET_PER_CONN_FLAGS;
  *reinterpret_cast<DWORD*>(&option.Value) = PROXY_TYPE_DIRECT;

  INTERNET_PER_CONN_OPTION_LISTW list{};
  list.dwSize = sizeof(list);
  list.dwOptionCount = 1;
  list.pOptions = &option;

  InternetSetOptionW(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list,
                     sizeof(list));
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_ENDSESSION && wparam) {
    DisableSystemProxyForSessionEnd();
  }

  // 让 Flutter 优先处理消息
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      // 字体设置改变时重新加载系统字体
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}