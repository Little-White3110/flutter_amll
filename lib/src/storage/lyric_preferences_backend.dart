import 'package:shared_preferences/shared_preferences.dart';

/// 歌词偏好的持久化后端。
///
/// 包内所有读写都经由本接口；宿主可替换为自有存储（数据库 / 多账号隔离 /
/// 内存实现用于测试）。默认为 [MemoryLyricPreferencesBackend]。
abstract class LyricPreferencesBackend {
  double? getDouble(String key);
  int? getInt(String key);
  bool? getBool(String key);
  String? getString(String key);
  Future<void> setDouble(String key, double value);
  Future<void> setInt(String key, int value);
  Future<void> setBool(String key, bool value);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

/// 内存版后端。
///
/// 作为 [LyricPreferences.backend] 的默认值：包在未注入宿主存储时也能正常工作
/// （偏好仅在当前进程有效）。测试可直接注入本类并用 [values] 断言。
class MemoryLyricPreferencesBackend implements LyricPreferencesBackend {
  /// 落库的键值快照，供测试断言。
  final Map<String, Object?> values = <String, Object?>{};

  @override
  double? getDouble(String key) => values[key] as double?;
  @override
  int? getInt(String key) => values[key] as int?;
  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  String? getString(String key) => values[key] as String?;
  @override
  Future<void> setDouble(String key, double value) async => values[key] = value;
  @override
  Future<void> setInt(String key, int value) async => values[key] = value;
  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
  @override
  Future<void> setString(String key, String value) async => values[key] = value;
  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// SharedPreferences 版后端：宿主 app 启动时注入。
///
/// ```dart
/// final prefs = await SharedPreferences.getInstance();
/// LyricPreferences.backend = SharedPrefsLyricPreferencesBackend(prefs);
/// await LyricPreferences.instance.load();
/// ```
class SharedPrefsLyricPreferencesBackend implements LyricPreferencesBackend {
  SharedPrefsLyricPreferencesBackend(this._prefs);

  final SharedPreferences _prefs;

  @override
  double? getDouble(String key) => _prefs.getDouble(key);
  @override
  int? getInt(String key) => _prefs.getInt(key);
  @override
  bool? getBool(String key) => _prefs.getBool(key);
  @override
  String? getString(String key) => _prefs.getString(key);
  @override
  Future<void> setDouble(String key, double value) async =>
      _prefs.setDouble(key, value);
  @override
  Future<void> setInt(String key, int value) async => _prefs.setInt(key, value);
  @override
  Future<void> setBool(String key, bool value) async =>
      _prefs.setBool(key, value);
  @override
  Future<void> setString(String key, String value) async =>
      _prefs.setString(key, value);
  @override
  Future<void> remove(String key) async => _prefs.remove(key);
}
