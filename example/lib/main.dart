import 'package:flutter/material.dart';
import 'package:flutter_amll/flutter_amll.dart';
import 'package:shared_preferences/shared_preferences.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 注入 SharedPreferences 后端，使 LyricPreferences 的读写真正落盘
  final prefs = await SharedPreferences.getInstance();
  LyricPreferences.backend = SharedPrefsLyricPreferencesBackend(prefs);
  await LyricPreferences.instance.load();
  runApp(const AmllExampleApp());
}

// 宿主注入点演示（此处不实际替换，宿主 App 可自行覆盖）：
// AmllHaptics.tick = () => MyHaptics.tick();          // 接回宿主的震动实现
// AmllFontLoader.pickFontFile = () => MyFont.pick();  // 接回宿主的字体选择器
// AmllToast.show = (msg) => MyToast.show(msg);        // 接回宿主的 Toast 实现

class AmllExampleApp extends StatelessWidget {
  const AmllExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_amll example',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const LyricsPreviewPage(),
    );
  }
}
