#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/event_sink.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <map>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  bool InstallPointerSubclass();
  void RemovePointerSubclass();
  void EmitPointerEvent(HWND hwnd, UINT32 pointer_id,
                        POINTER_INPUT_TYPE pointer_type,
                        const char* action) noexcept;
  void HandlePointerMessage(HWND hwnd, UINT const message,
                            WPARAM const wparam,
                            LPARAM lparam) noexcept;
  static LRESULT CALLBACK FlutterViewWindowProc(HWND hwnd, UINT message,
                                                WPARAM wparam, LPARAM lparam,
                                                UINT_PTR subclass_id,
                                                DWORD_PTR ref_data);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Event sink for pointer type events (pen/touch discrimination).
  std::unique_ptr<flutter::EventSink<>> event_sink_;

  // Map of pointer ID to device type (PT_PEN / PT_TOUCH / ...).
  std::map<uint32_t, int> pointer_device_types_;

  // Flutter child window that actually receives pointer input.
  HWND flutter_content_hwnd_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
