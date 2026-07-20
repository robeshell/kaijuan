#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kWindowChannelName[] = "com.kaika.kaika/window";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [window_handle = GetHandle()](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        const auto& method = call.method_name();
        if (method == "minimize") {
          ShowWindow(window_handle, SW_MINIMIZE);
          result->Success();
        } else if (method == "maximize") {
          ShowWindow(window_handle, SW_MAXIMIZE);
          result->Success();
        } else if (method == "restore") {
          ShowWindow(window_handle, SW_RESTORE);
          result->Success();
        } else if (method == "close") {
          PostMessage(window_handle, WM_CLOSE, 0, 0);
          result->Success();
        } else if (method == "isMaximized") {
          BOOL maximized = IsZoomed(window_handle);
          result->Success(flutter::EncodableValue(maximized != FALSE));
        } else if (method == "startDrag") {
          ReleaseCapture();
          SendMessage(window_handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

void FlutterWindow::NotifyMaximizedChanged() {
  if (!window_channel_) {
    return;
  }
  const bool maximized = IsZoomed(GetHandle()) != FALSE;
  if (has_reported_maximized_ && maximized == last_reported_maximized_) {
    return;
  }
  has_reported_maximized_ = true;
  last_reported_maximized_ = maximized;
  window_channel_->InvokeMethod(
      "maximizedChanged",
      std::make_unique<flutter::EncodableValue>(maximized));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_SIZE: {
      if (wparam == SIZE_MAXIMIZED || wparam == SIZE_RESTORED ||
          wparam == SIZE_MINIMIZED) {
        NotifyMaximizedChanged();
      }
      break;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
