import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_amll/flutter_amll.dart';

/// 设置面板（HEAD 版）在组件库注入点体系下可独立挂载。
///
/// 面板依赖的 CustomFontLoader / AppToast / RemoteSlider / LyricColorSettingTile
/// 均已改为组件库内实现或注入点；这里钉住「未注入任何宿主能力也不崩」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LyricPreferences.resetForTest();
    LyricPreferences.backend = MemoryLyricPreferencesBackend();
  });

  tearDown(() async {
    await LyricPreferences.instance.reset();
  });

  testWidgets('面板挂载：三项滑块 + 颜色 tile + 重置', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: LyricPreferencesPanel()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('歌词显示'), findsOneWidget);
    // 非 TV 构建走 M3ESlider（kTvBuild 默认 false），三项参数各一个。
    expect(find.byType(M3ESlider), findsNWidgets(3));
    expect(find.textContaining('字号'), findsOneWidget);
    expect(find.textContaining('字重'), findsOneWidget);
    expect(find.textContaining('行间距'), findsOneWidget);
    expect(find.text('自定义歌词颜色'), findsOneWidget);
    expect(find.text('歌词字体'), findsOneWidget);

    await tester.tap(find.text('重置'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('注入 AmllFontLoader 后选择字体路径为空时静默降级', (tester) async {
    // 默认注入返回 null，面板不会因缺少宿主文件选择器而抛异常。
    expect(await AmllFontLoader.pickFontFile(), isNull);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: LyricPreferencesPanel()),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
