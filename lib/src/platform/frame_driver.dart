import 'dart:async';

import 'package:flutter/foundation.dart';

/// 歌词组件共享的 60fps 帧驱动。
///
/// **为什么需要它**：歌词（AppleLyricsView 省电模式限帧）与封面旋转/频谱
/// 原本各自持有一个独立的 16ms Timer，两者启动时刻随机、相位错开，在 120Hz
/// 屏上整页实测 115~120fps（功耗近似翻倍），而单个组件都只要求 60fps。
/// 挂到同一节拍即可回到 60fps：各订阅者更新率不变，无视觉降级。
///
/// 语义：首个订阅者到来时启动定时器，最后一个订阅者离开时停掉（不留空转）。
class AmllFrameDriver {
  AmllFrameDriver._();

  static final AmllFrameDriver instance = AmllFrameDriver._();

  /// 步进周期（60fps）。与歌词 eco 限帧保持同一节拍。
  static const Duration step = Duration(milliseconds: 16);

  Timer? _timer;
  final List<VoidCallback> _listeners = <VoidCallback>[];

  /// 是否已有订阅者（诊断用）。
  bool get hasListeners => _listeners.isNotEmpty;

  /// 订阅共享节拍。
  void addListener(VoidCallback listener) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
    _timer ??= Timer.periodic(step, _onTick);
  }

  /// 取消订阅；最后一个订阅者离开时停掉定时器。
  void removeListener(VoidCallback listener) {
    if (!_listeners.remove(listener)) return;
    if (_listeners.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _onTick(Timer timer) {
    // 拷贝快照：回调内可能增删订阅（如收敛停帧）
    final List<VoidCallback> snapshot = List<VoidCallback>.of(_listeners);
    for (final VoidCallback cb in snapshot) {
      // 同一拍较早的回调可能销毁另一个订阅者；跳过已移除项，避免对已卸载
      // Widget 再触发一次 setState。
      if (_listeners.contains(cb)) cb();
    }
  }
}
