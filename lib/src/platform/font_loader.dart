import 'dart:io';

import 'package:flutter/services.dart';

/// 歌词自定义字体的加载与选择。
///
/// - [loadIfAvailable]：纯 Flutter 实现（[FontLoader] 动态注册），包内自带。
/// - [pickFontFile]：依赖宿主原生通道（Android SAF 文件选择器），包内无法提供，
///   默认返回 null；宿主注入自有实现：
///
/// ```dart
/// AmllFontLoader.pickFontFile = CustomFontLoader.pickFontFile;
/// ```
class AmllFontLoader {
  AmllFontLoader._();

  /// 注册到 Flutter 的自定义字体 family 名前缀。
  static const String customFontFamily = 'LyricUserCustomFont';
  static int _loadCounter = 0;

  /// 选择字体文件（宿主注入；未注入时返回 null）。
  static Future<String?> Function() pickFontFile = () async => null;

  /// Windows 端内置字体的 family（宿主注入；未注入时为 null，走系统字体链）。
  ///
  /// 源仓库对应 `WindowsDefaultFont.loadedFamily`（内置思源黑体，需宿主在启动时
  /// 调 `WindowsDefaultFont.load()` 注册）。组件库不打包字体资源，宿主注册成功后
  /// 把 family 写入本字段即可让偏好层的 `effectiveFontFamily` 取到它：
  ///
  /// ```dart
  /// AmllFontLoader.windowsDefaultFamily = WindowsDefaultFont.loadedFamily;
  /// ```
  static String? windowsDefaultFamily;

  /// 从持久化路径加载自定义 TTF/OTF，返回注册成功的 fontFamily，失败返回 null。
  static Future<String?> loadIfAvailable(String? fontPath) async {
    if (fontPath == null || fontPath.isEmpty) return null;
    final file = File(fontPath);
    if (!file.existsSync()) return null;
    try {
      final bytes = await file.readAsBytes();
      // 每次使用唯一 family name，避免 FontLoader 重复注册同一 family 抛异常
      _loadCounter++;
      final familyName = '$customFontFamily#$_loadCounter';
      final loader = FontLoader(familyName);
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      return familyName;
    } catch (_) {
      return null;
    }
  }
}
