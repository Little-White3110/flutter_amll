import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_amll/flutter_amll.dart';

/// 歌词渲染预览页（开发调试页）在组件库内可独立运行。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LyricPreferences.resetForTest();
    LyricPreferences.backend = MemoryLyricPreferencesBackend();
  });

  tearDown(() async {
    await LyricPreferences.instance.reset();
  });

  testWidgets('预览页挂载：Scaffold + AppleLyricsView + 时间滑块', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LyricsPreviewPage()));
    // 预览页用 AnimationController.repeat() 自动推进，不能用 pumpAndSettle。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('歌词预览'), findsOneWidget);
    expect(find.byType(AppleLyricsView), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('歌词文本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PopupMenu 切换 LRC 示例后仍能渲染', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LyricsPreviewPage()));
    await tester.pump();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump();
    await tester.tap(find.text('加载 LRC 示例'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(AppleLyricsView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
