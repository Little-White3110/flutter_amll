/// 「平衡行换行」偏好 lineBalance 的两态行为：默认开启、可持久化、reset 回默认。
///
/// 持久化 key 沿用宿主约定 `lyric_line_balance`（见项目长期记忆：偏好 key 保持
/// 原样，便于宿主 md3music 回接时用户设置延续）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_amll/src/layout/lyric_preferences.dart';
import 'package:flutter_amll/src/storage/lyric_preferences_backend.dart';

void main() {
  late MemoryLyricPreferencesBackend backend;

  setUp(() {
    LyricPreferences.resetForTest();
    backend = MemoryLyricPreferencesBackend();
    LyricPreferences.backend = backend;
    addTearDown(() => LyricPreferences.instance.reset());
  });

  test('默认开启平衡行换行', () {
    expect(LyricPreferences.instance.lineBalance, isTrue);
  });

  test('setter 先通知再落盘到 lyric_line_balance', () async {
    int notified = 0;
    void listener() => notified++;
    LyricPreferences.instance.addListener(listener);
    addTearDown(() => LyricPreferences.instance.removeListener(listener));

    await LyricPreferences.instance.setLineBalance(false);
    expect(notified, 1, reason: '值变化必须 notifyListeners，视图才能重算换行');
    expect(LyricPreferences.instance.lineBalance, isFalse);

    expect(backend.values['lyric_line_balance'], isFalse);
  });

  test('同值写入不重复通知（沿用仓内 setter 的门控写法）', () async {
    await LyricPreferences.instance.setLineBalance(false);
    int notified = 0;
    void listener() => notified++;
    LyricPreferences.instance.addListener(listener);
    addTearDown(() => LyricPreferences.instance.removeListener(listener));

    await LyricPreferences.instance.setLineBalance(false);
    expect(notified, 0);
  });

  test('reset 恢复默认开启', () async {
    await LyricPreferences.instance.setLineBalance(false);
    expect(LyricPreferences.instance.lineBalance, isFalse);

    await LyricPreferences.instance.reset();
    expect(LyricPreferences.instance.lineBalance, isTrue);
  });
}
