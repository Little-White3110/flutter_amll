/// 歌词设置面板的轻提示注入点。
///
/// 宿主 App 通常有统一的 Toast 实现（如 md3music 的 `showToast`，走
/// fluttertoast 原生通道）。包内不应引入 fluttertoast 这类第三方依赖，
/// 因此默认实现为空操作，由宿主注入：
///
/// ```dart
/// AmllToast.show = (msg, {long = false}) => showToast(msg, long: long);
/// ```
class AmllToast {
  AmllToast._();

  /// 显示一条轻提示。未注入时为空操作（静默，不抛异常）。
  static void Function(String msg, {bool long}) show = (msg, {long = false}) {};
}
