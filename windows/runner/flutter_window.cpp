#include "flutter_window.h"

#include <optional>
#include <chrono>

#include <commctrl.h>

#include "flutter/generated_plugin_registrant.h"

// Add required headers for EventChannel
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

// Windows pointer input types
#ifndef PT_POINTER
#define PT_POINTER 0x0001
#endif
#ifndef PT_TOUCH
#define PT_TOUCH 0x0002
#endif
#ifndef PT_PEN
#define PT_PEN 0x0003
#endif
#ifndef PT_MOUSE
#define PT_MOUSE 0x0004
#endif
#ifndef PT_TOUCHPAD
#define PT_TOUCHPAD 0x0005
#endif

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

namespace {

double ResolveDpiScale(HWND hwnd) {
  const double dpi_scale = static_cast<double>(GetDpiForWindow(hwnd)) / 96.0;
  return dpi_scale > 0.0 ? dpi_scale : 1.0;
}

void PopulatePointerPosition(flutter::EncodableMap& event,
                             const POINTER_INFO& pointer_info,
                             HWND hwnd) {
  POINT pt = pointer_info.ptPixelLocation;
  ScreenToClient(hwnd, &pt);

  const double safe_scale = ResolveDpiScale(hwnd);
  event[flutter::EncodableValue("x")] =
      flutter::EncodableValue(static_cast<double>(pt.x) / safe_scale);
  event[flutter::EncodableValue("y")] =
      flutter::EncodableValue(static_cast<double>(pt.y) / safe_scale);
}

}  // namespace

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // Enable WM_POINTER messages for pen/touch discrimination.
  // Required on Windows 8+ to receive unified pointer input that lets us
  // distinguish PT_PEN from PT_TOUCH via GetPointerType.
  EnableMouseInPointer(TRUE);

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  flutter_content_hwnd_ = flutter_controller_->view()->GetNativeWindow();
  InstallPointerSubclass();

  // Set up the pointer type event channel — broadcasts pen/touch events
  // to Dart so the viewer can route stylus input to crop control and
  // leave touch input to normal gestures.
  flutter::EventChannel<> pointer_type_channel(
      flutter_controller_->engine()->messenger(), "spnext/pointer_type",
      &flutter::StandardMethodCodec::GetInstance());

  pointer_type_channel.SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<>>(
          [this](auto arguments, auto events) {
            this->event_sink_ = std::move(events);
            return nullptr;
          },
          [this](auto arguments) {
            this->event_sink_ = nullptr;
            return nullptr;
          }));

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  event_sink_ = nullptr;
  RemovePointerSubclass();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::InstallPointerSubclass() {
  if (flutter_content_hwnd_ == nullptr) {
    return false;
  }
  return SetWindowSubclass(flutter_content_hwnd_, FlutterViewWindowProc, 1,
                           reinterpret_cast<DWORD_PTR>(this)) != 0;
}

void FlutterWindow::RemovePointerSubclass() {
  if (flutter_content_hwnd_ != nullptr) {
    RemoveWindowSubclass(flutter_content_hwnd_, FlutterViewWindowProc, 1);
    flutter_content_hwnd_ = nullptr;
  }
}

LRESULT CALLBACK FlutterWindow::FlutterViewWindowProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR subclass_id,
    DWORD_PTR ref_data) {
  auto* window = reinterpret_cast<FlutterWindow*>(ref_data);
  if (window != nullptr) {
    if (message == WM_POINTERDOWN || message == WM_POINTERUPDATE ||
        message == WM_POINTERUP || message == WM_POINTERLEAVE) {
      window->HandlePointerMessage(hwnd, message, wparam, lparam);
    }
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

void FlutterWindow::EmitPointerEvent(HWND hwnd, UINT32 pointerId,
                                     POINTER_INPUT_TYPE pointerType,
                                     const char* action) noexcept {
  if (!event_sink_) {
    return;
  }

  flutter::EncodableMap event;
  event[flutter::EncodableValue("pointerId")] =
      flutter::EncodableValue(static_cast<int>(pointerId));
  event[flutter::EncodableValue("type")] =
      flutter::EncodableValue(static_cast<int>(pointerType));
  event[flutter::EncodableValue("action")] =
      flutter::EncodableValue(action);

  POINTER_INFO pointerInfo;
  if (GetPointerInfo(pointerId, &pointerInfo)) {
    PopulatePointerPosition(event, pointerInfo, hwnd);
  }

  const auto now = std::chrono::high_resolution_clock::now();
  const auto microseconds = std::chrono::duration_cast<std::chrono::microseconds>(
                                now.time_since_epoch())
                                .count();
  event[flutter::EncodableValue("timestamp")] =
      flutter::EncodableValue(microseconds);

  event_sink_->Success(flutter::EncodableValue(event));
}

void FlutterWindow::HandlePointerMessage(HWND hwnd, UINT const message,
                                         WPARAM const wparam,
                                         LPARAM const lparam) noexcept {
  UINT32 pointerId = GET_POINTERID_WPARAM(wparam);
  POINTER_INPUT_TYPE pointerType;

  if (message == WM_POINTERLEAVE) {
    if (event_sink_) {
      auto it = pointer_device_types_.find(pointerId);
      if (it != pointer_device_types_.end()) {
        pointerType = static_cast<POINTER_INPUT_TYPE>(it->second);
      } else if (!GetPointerType(pointerId, &pointerType)) {
        pointerType = PT_POINTER;
      }
      EmitPointerEvent(hwnd, pointerId, pointerType, "leave");
    }
    pointer_device_types_.erase(pointerId);
    return;
  }

  if (!GetPointerType(pointerId, &pointerType)) {
    return;
  }

  pointer_device_types_[pointerId] = pointerType;
  EmitPointerEvent(
      hwnd, pointerId, pointerType,
      message == WM_POINTERDOWN ? "down"
      : message == WM_POINTERUP ? "up"
                                 : "move");
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_POINTERDOWN || message == WM_POINTERUPDATE ||
      message == WM_POINTERUP || message == WM_POINTERLEAVE) {
    if (flutter_content_hwnd_ == nullptr || hwnd != GetHandle()) {
      HandlePointerMessage(hwnd, message, wparam, lparam);
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
