import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Windows 原生指针设备类型 — 与 C++ 层 PT_* 宏对齐。
///
/// 由 `windows/runner/flutter_window.cpp` 通过 EventChannel
/// `spnext/pointer_type` 上报。用于在单图查看器中区分手写笔与触摸屏：
/// 手写笔输入路由到裁剪控制，触摸输入保留给 InteractiveViewer 手势。
enum WindowsPointerType {
  pointer(0x0001),
  touch(0x0002),
  pen(0x0003),
  mouse(0x0004),
  touchpad(0x0005),
  unknown(0);

  final int value;
  const WindowsPointerType(this.value);

  static WindowsPointerType fromValue(int value) {
    return WindowsPointerType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => WindowsPointerType.unknown,
    );
  }

  bool get isPen => this == WindowsPointerType.pen;
  bool get isTouch => this == WindowsPointerType.touch;
  bool get isMouse => this == WindowsPointerType.mouse;
}

/// 来自 Windows 原生层的指针事件。
///
/// 仅包含区分手写笔/触摸所需的最少信息：pointerId、type、action、
/// 窗口客户区坐标（已按 DPI 缩放回逻辑像素）、时间戳。
/// 不包含压感/倾斜 — 裁剪控制不需要这些数据。
class WindowsPointerEvent {
  final int pointerId;
  final WindowsPointerType type;
  final String action; // "down" | "move" | "up" | "leave"

  /// 窗口客户区逻辑坐标（已除以 DPI scale，对应 Flutter 全局坐标）。
  final double? x;
  final double? y;

  /// 微秒级时间戳（自 epoch）。
  final int? timestamp;

  WindowsPointerEvent({
    required this.pointerId,
    required this.type,
    required this.action,
    this.x,
    this.y,
    this.timestamp,
  });

  factory WindowsPointerEvent.fromMap(Map<dynamic, dynamic> map) {
    return WindowsPointerEvent(
      pointerId: map['pointerId'] as int,
      type: WindowsPointerType.fromValue(map['type'] as int? ?? 0),
      action: map['action'] as String,
      x: (map['x'] as num?)?.toDouble(),
      y: (map['y'] as num?)?.toDouble(),
      timestamp: map['timestamp'] as int?,
    );
  }

  @override
  String toString() =>
      'WindowsPointerEvent(id=$pointerId, type=$type, action=$action, '
      'x=$x, y=$y)';
}

/// 接收 Windows 原生指针类型事件的服务。
///
/// 通过 EventChannel `spnext/pointer_type` 监听 C++ 层上报的 WM_POINTER
/// 事件，广播给 UI 层。UI 层据此判断当前输入来自手写笔还是触摸屏，
/// 并在时间窗口内将 Flutter PointerEvent 关联到对应的设备类型。
///
/// 仅在 Windows 平台可用；其他平台 [initialize] 为空操作，
/// [events] 永远不会发射事件。
class PointerTypeService {
  static const _channelName = 'spnext/pointer_type';

  static final PointerTypeService _instance = PointerTypeService._internal();
  factory PointerTypeService() => _instance;
  PointerTypeService._internal();

  EventChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  /// pointerId → 最近一次事件类型。用于查询某个 Flutter pointer 是否为笔。
  final Map<int, WindowsPointerType> _pointerTypes = {};

  /// 最近一次手写笔事件时间 — 用于在 Flutter PointerEvent 到达时
  /// 判断是否"刚刚"有笔输入（Flutter 与原生事件存在时序差）。
  DateTime? _lastPenEventTime;

  /// 最近一次触摸事件时间。
  DateTime? _lastTouchEventTime;

  final _eventController = StreamController<WindowsPointerEvent>.broadcast();
  Stream<WindowsPointerEvent> get events => _eventController.stream;

  /// 是否已初始化（仅 Windows 平台为 true）。
  bool get isInitialized => _subscription != null;

  /// 初始化服务 — 在 app 启动时调用一次。非 Windows 平台为空操作。
  void initialize() {
    if (!Platform.isWindows) {
      debugPrint('[PointerTypeService] non-Windows, skip');
      return;
    }

    debugPrint('[PointerTypeService] initializing EventChannel spnext/pointer_type...');
    try {
      _channel = const EventChannel(_channelName);
      _subscription = _channel?.receiveBroadcastStream().listen(
        (dynamic event) {
          try {
            if (event is! Map) return;
            final pointerEvent = WindowsPointerEvent.fromMap(event);
            _pointerTypes[pointerEvent.pointerId] = pointerEvent.type;

            final now = DateTime.now();
            if (pointerEvent.type.isPen) {
              _lastPenEventTime = now;
              debugPrint(
                  '[PointerTypeService] PEN event: id=${pointerEvent.pointerId} '
                  'action=${pointerEvent.action} x=${pointerEvent.x} y=${pointerEvent.y}');
            } else if (pointerEvent.type.isTouch) {
              _lastTouchEventTime = now;
              debugPrint(
                  '[PointerTypeService] TOUCH event: id=${pointerEvent.pointerId} '
                  'action=${pointerEvent.action}');
            }

            _eventController.add(pointerEvent);

            if (pointerEvent.action == 'up' || pointerEvent.action == 'leave') {
              Future.delayed(const Duration(milliseconds: 100), () {
                _pointerTypes.remove(pointerEvent.pointerId);
              });
            }
          } catch (e, stackTrace) {
            debugPrint('PointerTypeService parse error: $e\n$stackTrace');
          }
        },
        onError: (dynamic error, dynamic stackTrace) {
          debugPrint('[PointerTypeService] stream ERROR: $error\n$stackTrace');
        },
      );
      debugPrint('[PointerTypeService] initialized, listening...');
    } catch (e, stackTrace) {
      debugPrint('[PointerTypeService] init FAILED: $e\n$stackTrace');
    }
  }

  /// 释放资源。
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _eventController.close();
  }

  /// 查询某个 pointerId 的设备类型。
  WindowsPointerType getPointerType(int pointerId) {
    return _pointerTypes[pointerId] ?? WindowsPointerType.unknown;
  }

  /// 最近是否有手写笔事件（在 [maxAge] 时间窗口内）。
  bool hasRecentPenEvent({Duration maxAge = const Duration(milliseconds: 200)}) {
    if (_lastPenEventTime == null) return false;
    return DateTime.now().difference(_lastPenEventTime!) <= maxAge;
  }

  /// 最近是否有触摸事件（在 [maxAge] 时间窗口内）。
  bool hasRecentTouchEvent(
      {Duration maxAge = const Duration(milliseconds: 200)}) {
    if (_lastTouchEventTime == null) return false;
    return DateTime.now().difference(_lastTouchEventTime!) <= maxAge;
  }
}