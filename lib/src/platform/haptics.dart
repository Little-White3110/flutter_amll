import 'package:flutter/services.dart';

/// 歌词交互的触觉反馈注入点。
///
/// 默认使用 Flutter [HapticFeedback]；宿主可整体替换为自有实现
/// （如 md3music 的 AppHaptics，走原生 VibratorManager 直写马达）：
///
/// ```dart
/// AmllHaptics.tick = AppHaptics.tick;
/// ```
class AmllHaptics {
  AmllHaptics._();

  /// 刻度反馈（歌词行点击 / 滚动刻度）。默认 selectionClick。
  static void Function() tick = () => HapticFeedback.selectionClick();

  /// 轻点反馈。默认 lightImpact。
  static void Function() click = () => HapticFeedback.lightImpact();
}
