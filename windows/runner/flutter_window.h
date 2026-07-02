// UTF-8 BOM
#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// 承载 Flutter 视图的窗口
class FlutterWindow : public Win32Window {
 public:
  // 创建新的 FlutterWindow 并承载 Flutter 视图
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window 回调
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Flutter 项目配置
  flutter::DartProject project_;

  void HandleSessionMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void DisableSystemProxyForSessionEnd();

  // Flutter 视图控制器
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> session_channel_;
  bool should_disable_system_proxy_on_session_end_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_