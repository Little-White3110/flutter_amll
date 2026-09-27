# AM 歌词 UI（AMLL）抽取到 flutter_amll 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `private_md3music` 中 AM（Apple Music）风格播放页使用的歌词 UI —— `lib/widgets/apple_lyrics/**` 全套渲染/解析/偏好实现及其 22 个测试 —— 完整抽到独立仓库 `flutter_amll`，成为一个零宿主耦合、可独立运行的 Flutter 组件库；原仓库只读、不做任何修改。

**Architecture:** `flutter_amll` 是一个 Flutter package（`publish_to: none`）。源码按原目录结构镜像迁移到 `lib/src/`，保持文件内部相对 import 全部有效；仅把 3 个宿主服务（帧驱动 / 触觉 / 字体加载）降级为包内实现 + 可注入接口，把 SharedPreferences 读写收口到一个极简后端接口。对外只暴露 `lib/flutter_amll.dart` 门面。附一个 `example/` app 承载原 `preview/lyrics_preview_page.dart` 调试页。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4；`m3e_core ^1.1.4`、`material_ui ^1.3.0`、`xml ^6.5.0`（TTML）、`shared_preferences ^2.5.0`；测试用 `flutter_test` + `fake_async`。

---

## 0. 现状勘察结论（事实基线）

源：`C:\Users\32732\Desktop\TRAE SOLO\private_md3music`（分支 `rust-local-two`，版本 5.7.0+45，**全程只读**）
目标：`C:\Users\32732\Desktop\TRAE SOLO\flutter_amll`（当前空目录，无 git）

### 0.1 迁移清单（20 个源文件，11,479 行）

| 源文件（`lib/widgets/apple_lyrics/`） | 行数 | 迁移到 |
|---|---|---|
| `apple_lyrics_view.dart` | 3376 | `lib/src/apple_lyrics_view.dart` |
| `renderers/word_renderer.dart` | 2202 | `lib/src/renderers/word_renderer.dart` |
| `renderers/line_renderer.dart` | 789 | `lib/src/renderers/line_renderer.dart` |
| `renderers/emphasize_effect.dart` | — | `lib/src/renderers/emphasize_effect.dart` |
| `renderers/interlude_dots.dart` | — | `lib/src/renderers/interlude_dots.dart` |
| `layout/lyric_preferences.dart` | 762 | `lib/src/layout/lyric_preferences.dart` |
| `layout/lyric_layout.dart` | 494 | `lib/src/layout/lyric_layout.dart` |
| `layout/duet_layout.dart` | — | `lib/src/layout/duet_layout.dart` |
| `layout/lyric_preferences_panel.dart` | — | `lib/src/layout/lyric_preferences_panel.dart` |
| `controllers/lyric_scroll_controller.dart` | 333 | `lib/src/controllers/lyric_scroll_controller.dart` |
| `controllers/line_scale_controller.dart` | — | `lib/src/controllers/line_scale_controller.dart` |
| `models/lyric_line.dart` | — | `lib/src/models/lyric_line.dart` |
| `animation/spring.dart` | — | `lib/src/animation/spring.dart` |
| `parsers/lyric_parser_chain.dart` | — | `lib/src/parsers/lyric_parser_chain.dart` |
| `parsers/krc_parser.dart` / `lrc_parser.dart` / `ttml_parser.dart` / `plaintext_parser.dart` | — | `lib/src/parsers/*` |
| `utils/lyric_position.dart` | 8 | `lib/src/utils/lyric_position.dart` |
| `preview/lyrics_preview_page.dart` | 206 | `example/lib/preview/lyrics_preview_page.dart` |

测试（22 个文件，约 5,700 行）：`test/widgets/apple_lyrics/**` → `test/**`（保持子目录 `animation/ controllers/ layout/ models/ parsers/ renderers/`）。

### 0.2 依赖边界（必须处理的耦合）

| 依赖 | 使用位置 | 处理策略 |
|---|---|---|
| `package:md3music/widgets/apple_lyrics/...`（含 12 处 `models/lyric_line.dart`） | 全树 | 批量重写为 `package:flutter_amll/src/...` |
| `../../core/services/player_frame_driver.dart`（`PlayerFrameDriver.instance/step`，5 处） | `apple_lyrics_view.dart` | 内置副本 `src/platform/frame_driver.dart`，类名 `AmllFrameDriver` |
| `../../core/utils/app_haptics.dart`（`AppHaptics.tick()`，1 处 @2169） | `apple_lyrics_view.dart` | 内置 `src/platform/haptics.dart`，类名 `AmllHaptics`，默认走 `HapticFeedback.selectionClick`，允许宿主覆写 |
| `../../../core/services/custom_font_loader.dart`（`CustomFontLoader.pickFontFile()` @207 + `loadIfAvailable`） | `layout/lyric_preferences_panel.dart`、`layout/lyric_preferences.dart` | 内置 `src/platform/font_loader.dart`，类名 `AmllFontLoader`；`pickFontFile` 改为可注入回调（默认返回 null，宿主注入原生 SAF 选择） |
| `../../../core/utils/app_toast.dart` | `lyric_preferences_panel.dart:5` | **仅 import、无调用** → 删除该 import |
| `package:material_ui/material_ui.dart` | `apple_lyrics_view.dart:20`（无符号引用）、`lyric_preferences_panel.dart:1`、`preview` | 保留 pub 依赖；`apple_lyrics_view.dart` 若 `flutter analyze` 报 unused_import 则删除该行 |
| `package:m3e_core/m3e_core.dart` | `lyric_preferences_panel.dart:2`（`M3ESlider` ×3）、`preview`（`showM3EModalBottomSheet`） | 保留 pub 依赖（面板 UI 与预览页依赖） |
| `package:shared_preferences` | `lyric_preferences.dart` | 收口到 `src/storage/lyric_preferences_backend.dart`，默认实现同名 key |
| `package:xml` | `ttml_parser.dart` | 保留 |

### 0.3 必须原样保留的优化点（迁移后回归核对清单）

逐字 mask 渲染 + 整行降级 · Ticker 驱动的弹簧动画 · 二分查找当前行 · eco 60fps 共享节拍限帧 · 模糊层脏标记缓存（`_lastBlurRebuild*`）· 每帧重绘阈值（0.5px / 0.001）· `positionListenable` 内部订阅解耦（避免父级 200ms 重建）· `playbackNotReady` 时钟冻结 · 辉光阈值（BPM/字长中位数）· 间奏点节奏动画 · 对唱（duet）布局 · 非当前行高斯模糊 + `inactiveScale` 双层共用 · 级联错峰（三参数）· 已播字上浮 · 动态字体颜色（70% 白 + 30% 封面提取色）· 单击/双击跳转 · Pad/手机差异化默认值。

### 0.4 必须原样保留的可调选项

`LyricPreferences`（762 行）全部 20 项持久化选项：`fontSize` `lineSpacing` `fontWeightValue` `useGaussianBlur` `blurIntensity` `useGlowEffect` `useFlowingBackground` `useDuetLayout` `showTranslation` `displayMode` `fontSource` `customFontPath` `ecoMode` `useDynamicLyricColor` `glowThresholdFactor` `inactiveScale` `alignPosition` `cascadeMaxDelayMs` `cascadeBaseStepMs` `cascadeDecayX` `liftHeightPx` `staggerFromCurrentLine`，以及各自 min/max/default 常量与滑块档位常量、SharedPreferences key（**保持原名，不做前缀改动**，保证与宿主 app 升级兼容）。

`AppleLyricsView` 11 个构造参数：`lines` `currentTimeMs` `isPlaying` `playbackNotReady` `onSeek` `enableScale` `forceDarkBackground` `enableInterludeDots` `doubleTapToJump` `accentColor` `songBpm` `positionListenable` `adaptTimeMs`。

### 0.5 非目标（明确不做）

- 不迁移 `Md3LyricPreferences` / `md3_lyric_preferences_panel.dart`（MD3 风格另一套歌词，与 AM 无关）
- 不迁移 `full_player_am.dart`、`lyrics_view.dart`、`car_mode_lyric_bar.dart`、`desktop_lyric_service.dart`、`media_notification_service.dart`（宿主消费方）
- 不修改、不提交、不 `git checkout` 原仓库任何文件
- 不做视觉/逻辑重构、不重命名字段、不改默认值（karpathy：手术式迁移）

---

## 1. 任务列表

### Task 1: 建立 package 骨架

**Files:**
- Create: `pubspec.yaml`、`analysis_options.yaml`、`.gitignore`
- Create: `lib/flutter_amll.dart`（Task 5 填充）

- [ ] **Step 1: 写 pubspec.yaml**

```yaml
name: flutter_amll
description: Apple Music 风格（AMLL）逐字歌词渲染组件库，自 md3music 抽取。
version: 0.1.0
publish_to: 'none'

environment:
  sdk: ^3.12.0
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter
  # 偏好面板使用 M3ESlider；预览页使用 showM3EModalBottomSheet
  m3e_core: ^1.1.4
  # material_ui 1.3.0 实际要求 Flutter >= 3.47（用了 @awaitNotRequired）
  material_ui: ^1.3.0
  # 歌词偏好持久化
  shared_preferences: ^2.5.0
  # TTML（Apple Music XML 歌词）解析
  xml: ^6.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  fake_async: ^1.3.1

flutter:
  uses-material-design: true
```

- [ ] **Step 2: 写 analysis_options.yaml**

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    # 迁移期允许 src 内部互相 import（测试需直接导入 renderers/controllers）
    implementation_imports: ignore
  exclude:
    - build/**

linter:
  rules:
    prefer_const_constructors: false
    prefer_const_declarations: false
```

- [ ] **Step 3: 写 .gitignore**

```
.dart_tool/
.packages
build/
.pub-cache/
.pub/
.idea/
.fvm/
*.iml
coverage/
```

- [ ] **Step 4: 验证**

Run: `cd "C:/Users/32732/Desktop/TRAE SOLO/flutter_amll" && flutter pub get`
Expected: 解析成功，无 version solving failed。

---

### Task 2: 复制源码树并批量重写 import

**Files:**
- Create: `lib/src/**`（20 个文件的镜像）

- [ ] **Step 1: 整树复制（源仓库只读）**

```bash
SRC="C:/Users/32732/Desktop/TRAE SOLO/private_md3music"
DST="C:/Users/32732/Desktop/TRAE SOLO/flutter_amll"
mkdir -p "$DST/lib/src"
cp -r "$SRC/lib/widgets/apple_lyrics/." "$DST/lib/src/"
rm -rf "$DST/lib/src/preview"     # preview 归属 example，见 Task 6
```

- [ ] **Step 2: 重写 package import**

```bash
find "$DST/lib" -name "*.dart" -print0 | \
  xargs -0 sed -i "s#package:md3music/widgets/apple_lyrics/#package:flutter_amll/src/#g"
```

- [ ] **Step 3: 验证零逻辑改动**

Run:
```bash
diff -u "$SRC/lib/widgets/apple_lyrics/animation/spring.dart" "$DST/lib/src/animation/spring.dart"
diff -u "$SRC/lib/widgets/apple_lyrics/models/lyric_line.dart" "$DST/lib/src/models/lyric_line.dart"
```
Expected: 两条命令均无输出（这两个文件无 package import，应逐字节一致）。

Run: `cd "$DST" && grep -rl "package:md3music" lib | wc -l`
Expected: `0`

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "chore: import apple_lyrics source tree from md3music"
```

---

### Task 3: 解耦三个宿主平台服务

**Files:**
- Create: `lib/src/platform/frame_driver.dart`
- Create: `lib/src/platform/haptics.dart`
- Create: `lib/src/platform/font_loader.dart`
- Modify: `lib/src/apple_lyrics_view.dart`（import + 5 处 `PlayerFrameDriver` + 1 处 `AppHaptics`）
- Modify: `lib/src/layout/lyric_preferences_panel.dart`（import + `CustomFontLoader.pickFontFile`）

- [ ] **Step 1: `lib/src/platform/frame_driver.dart`**（`PlayerFrameDriver` 原样副本，仅改类名）

```dart
import 'dart:async';

/// 歌词组件共享的 60fps 帧驱动。
///
/// 语义与来源实现完全一致：首个订阅者到来时启动定时器，最后一个订阅者
/// 离开时停掉；同一节拍回调，快照遍历 + 移除校验。
class AmllFrameDriver {
  AmllFrameDriver._();
  static final AmllFrameDriver instance = AmllFrameDriver._();

  /// 步进周期（60fps），与歌词 eco 限帧保持同一节拍。
  static const Duration step = Duration(milliseconds: 16);

  Timer? _timer;
  final List<VoidCallback> _listeners = <VoidCallback>[];

  bool get hasListeners => _listeners.isNotEmpty;

  void addListener(VoidCallback listener) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
    _timer ??= Timer.periodic(step, _onTick);
  }

  void removeListener(VoidCallback listener) {
    if (!_listeners.remove(listener)) return;
    if (_listeners.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _onTick(Timer timer) {
    final List<VoidCallback> snapshot = List<VoidCallback>.of(_listeners);
    for (final VoidCallback cb in snapshot) {
      if (_listeners.contains(cb)) cb();
    }
  }
}
```

- [ ] **Step 2: `lib/src/platform/haptics.dart`**

```dart
import 'package:flutter/services.dart';

/// 歌词交互触觉反馈。
///
/// 默认使用 Flutter [HapticFeedback]；宿主可整体替换为自有实现
/// （如 md3music 的 AppHaptics，走原生 VibratorManager）：
///
/// ```dart
/// AmllHaptics.tick = AppHaptics.tick;
/// ```
class AmllHaptics {
  AmllHaptics._();

  /// 刻度反馈（歌词行点击/滚动刻度）。默认 selectionClick。
  static void Function() tick = () => HapticFeedback.selectionClick();

  /// 轻点反馈。默认 lightImpact。
  static void Function() click = () => HapticFeedback.lightImpact();
}
```

- [ ] **Step 3: `lib/src/platform/font_loader.dart`**

```dart
import 'dart:io';

import 'package:flutter/services.dart';

/// 歌词自定义字体加载与选择。
///
/// - [loadIfAvailable]：纯 Flutter，包内自带实现（[FontLoader] 动态注册）。
/// - [pickFontFile]：依赖宿主原生通道，包内无法提供；默认返回 null，
///   宿主注入自有实现：
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

  /// 从持久化路径加载自定义 TTF，返回注册成功的 fontFamily，失败返回 null。
  static Future<String?> loadIfAvailable(String? fontPath) async {
    if (fontPath == null || fontPath.isEmpty) return null;
    final file = File(fontPath);
    if (!file.existsSync()) return null;
    try {
      final bytes = await file.readAsBytes();
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
```

- [ ] **Step 4: 改写调用点**

`lib/src/apple_lyrics_view.dart`：
```bash
sed -i \
  -e "s#import '../../core/utils/app_haptics.dart';#import 'platform/haptics.dart';#" \
  -e "s#import '../../core/services/player_frame_driver.dart';#import 'platform/frame_driver.dart';#" \
  -e "s#\bPlayerFrameDriver\b#AmllFrameDriver#g" \
  -e "s#AppHaptics\.tick()#AmllHaptics.tick()#g" \
  "$DST/lib/src/apple_lyrics_view.dart"
```

`lib/src/layout/lyric_preferences_panel.dart`：
```bash
sed -i \
  -e "s#import '../../../core/services/custom_font_loader.dart';#import '../platform/font_loader.dart';#" \
  -e "/import '..\/..\/..\/core\/utils\/app_toast.dart';/d" \
  -e "s#CustomFontLoader\.#AmllFontLoader.#g" \
  "$DST/lib/src/layout/lyric_preferences_panel.dart"
```

- [ ] **Step 5: 验证**

Run: `cd "$DST" && grep -rn "core/services\|core/utils\|AppHaptics\|PlayerFrameDriver\|CustomFontLoader\|app_toast" lib || echo CLEAN`
Expected: 输出 `CLEAN`。

Run: `cd "$DST" && diff -u "$SRC/lib/widgets/apple_lyrics/apple_lyrics_view.dart" lib/src/apple_lyrics_view.dart | grep -c "^[+-]"`
Expected: ≤ 20（仅 import 行 + 7 处符号改名，注释中的类名引用一并改名）。

- [ ] **Step 6: 提交**

```bash
git add -A && git commit -m "refactor: decouple frame driver, haptics and font loader from host app"
```

---

### Task 4: 偏好存储抽象（保留全部 key 与默认值）

**Files:**
- Create: `lib/src/storage/lyric_preferences_backend.dart`
- Modify: `lib/src/layout/lyric_preferences.dart`（仅替换 `SharedPreferences.getInstance()` 调用点）

- [ ] **Step 1: 写后端接口**

```dart
/// 歌词偏好的持久化后端。
///
/// 默认实现走 SharedPreferences 且沿用原 key 名；宿主可替换为自有存储
/// （数据库 / 多账号隔离 / 内存实现用于测试）。
abstract class LyricPreferencesBackend {
  double? getDouble(String key);
  int? getInt(String key);
  bool? getBool(String key);
  String? getString(String key);
  Future<void> setDouble(String key, double value);
  Future<void> setInt(String key, int value);
  Future<void> setBool(String key, bool value);
  Future<void> setString(String key, String value);
}

/// 基于 SharedPreferences 的默认后端。
///
/// [instance] 必须在首次读写前通过 [bootstrap] 注入（通常在 app 启动时
/// await 一次），之后所有读写均为同步命中缓存。
class SharedPrefsLyricPreferencesBackend implements LyricPreferencesBackend {
  SharedPrefsLyricPreferencesBackend(this._prefs);

  final dynamic _prefs;

  /// 启动注入：`await SharedPrefsLyricPreferencesBackend.bootstrap()`。
  static Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    LyricPreferences.backend = SharedPrefsLyricPreferencesBackend(prefs);
  }

  @override
  double? getDouble(String key) => _prefs.getDouble(key) as double?;
  @override
  int? getInt(String key) => _prefs.getInt(key) as int?;
  @override
  bool? getBool(String key) => _prefs.getBool(key) as bool?;
  @override
  String? getString(String key) => _prefs.getString(key) as String?;
  @override
  Future<void> setDouble(String key, double value) => _prefs.setDouble(key, value) as Future<void>;
  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value) as Future<void>;
  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value) as Future<void>;
  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value) as Future<void>;
}
```

> 说明：用 `dynamic _prefs` 是为了避免 `shared_preferences` 的 `SharedPreferencesAsync` 泛型差异；若 analyzer 报类型问题，改为显式 `SharedPreferences` 类型并补充 `import 'package:shared_preferences/shared_preferences.dart';`。

- [ ] **Step 2: 在 `lyric_preferences.dart` 中接入**

在 `LyricPreferences` 类中新增静态字段，并把 `load()` 与各 setter 中
`await SharedPreferences.getInstance()` 替换为 `LyricPreferences.backend`：

```dart
class LyricPreferences extends ChangeNotifier {
  /// 持久化后端；默认为空实现（读写返回 null / no-op），宿主启动时注入。
  static LyricPreferencesBackend backend = _NoopLyricPreferencesBackend();
  ...
}
```

同时新增（同文件内私有类）：

```dart
class _NoopLyricPreferencesBackend implements LyricPreferencesBackend {
  @override double? getDouble(String key) => null;
  @override int? getInt(String key) => null;
  @override bool? getBool(String key) => null;
  @override String? getString(String key) => null;
  @override Future<void> setDouble(String key, double value) async {}
  @override Future<void> setInt(String key, int value) async {}
  @override Future<void> setBool(String key, bool value) async {}
  @override Future<void> setString(String key, String value) async {}
}
```

`load()` 首行改为：`if (_loaded) return;` 保持不变，随后所有 `prefs.getX(_keyX)` 改为 `backend.getX(_keyX)`。

- [ ] **Step 3: 验证 key 与默认值零漂移**

Run:
```bash
cd "$DST" && diff <(grep -oE "static const String _key[A-Za-z]+ = '[^']+'" "$SRC/lib/widgets/apple_lyrics/layout/lyric_preferences.dart" | sort) \
                <(grep -oE "static const String _key[A-Za-z]+ = '[^']+'" lib/src/layout/lyric_preferences.dart | sort) && echo KEYS_IDENTICAL
```
Expected: `KEYS_IDENTICAL`

Run:
```bash
cd "$DST" && diff <(grep -oE "static const (double|int|bool) (min|max|default)[A-Za-z]+" "$SRC/lib/widgets/apple_lyrics/layout/lyric_preferences.dart" | sort) \
                <(grep -oE "static const (double|int|bool) (min|max|default)[A-Za-z]+" lib/src/layout/lyric_preferences.dart | sort) && echo CONSTS_IDENTICAL
```
Expected: `CONSTS_IDENTICAL`

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "refactor: introduce injectable preferences backend, keep all keys and defaults"
```

---

### Task 5: 公开 API 门面

**Files:**
- Create: `lib/flutter_amll.dart`

- [ ] **Step 1: 写门面**

```dart
/// flutter_amll —— Apple Music 风格（AMLL）逐字歌词渲染组件库。
///
/// 自 md3music 的 AM 风格播放页歌词 UI 抽取，保留全部渲染优化与可调节选项，
/// 且不依赖任何宿主业务代码。
library;

export 'src/animation/spring.dart';
export 'src/apple_lyrics_view.dart';
export 'src/controllers/line_scale_controller.dart';
export 'src/controllers/lyric_scroll_controller.dart';
export 'src/layout/duet_layout.dart';
export 'src/layout/lyric_layout.dart';
export 'src/layout/lyric_preferences.dart';
export 'src/layout/lyric_preferences_panel.dart';
export 'src/models/lyric_line.dart';
export 'src/parsers/krc_parser.dart';
export 'src/parsers/lrc_parser.dart';
export 'src/parsers/lyric_parser_chain.dart';
export 'src/parsers/plaintext_parser.dart';
export 'src/parsers/ttml_parser.dart';
export 'src/platform/font_loader.dart';
export 'src/platform/frame_driver.dart';
export 'src/platform/haptics.dart';
export 'src/storage/lyric_preferences_backend.dart';
export 'src/utils/lyric_position.dart';
```

> `renderers/*` 为渲染内部实现，不对外导出；测试与 example 通过
> `import 'package:flutter_amll/src/renderers/word_renderer.dart';` 直接引用。

- [ ] **Step 2: 验证门面自洽**

Run: `cd "$DST" && flutter analyze lib/flutter_amll.dart`
Expected: `No issues found!`

- [ ] **Step 3: 提交**

```bash
git add -A && git commit -m "feat: expose public API facade"
```

---

### Task 6: 迁移预览页到 example

**Files:**
- Create: `example/lib/preview/lyrics_preview_page.dart`
- Create: `example/pubspec.yaml`、`example/lib/main.dart`

- [ ] **Step 1: 复制并改写 import**

```bash
mkdir -p "$DST/example/lib/preview"
cp "$SRC/lib/widgets/apple_lyrics/preview/lyrics_preview_page.dart" "$DST/example/lib/preview/"
sed -i "s#package:md3music/widgets/apple_lyrics/#package:flutter_amll/src/#g" "$DST/example/lib/preview/lyrics_preview_page.dart"
```

- [ ] **Step 2: 写 example/pubspec.yaml**

```yaml
name: flutter_amll_example
description: Demo app for the flutter_amll lyrics package.
publish_to: 'none'

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter
  flutter_amll:
    path: ../
  m3e_core: ^1.1.4
  material_ui: ^1.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
```

- [ ] **Step 3: 写 example/lib/main.dart**

入口需完成两件事：注入偏好后端（否则偏好不持久化）、打开预览页。

```dart
import 'package:flutter/material.dart';
import 'package:flutter_amll/flutter_amll.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'preview/lyrics_preview_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 注入 SharedPreferences 后端，使 LyricPreferences 的读写生效
  final prefs = await SharedPreferences.getInstance();
  LyricPreferences.backend = SharedPrefsLyricPreferencesBackend(prefs);
  await LyricPreferences.instance.load();
  runApp(const AmllExampleApp());
}

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
```

> example 需额外声明 `shared_preferences: ^2.5.0`（用于注入后端）；若 analyzer 提示未声明，补进 example/pubspec.yaml。

- [ ] **Step 4: 验证 example 可分析**

Run: `cd "$DST/example" && flutter pub get && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 提交**

```bash
git add -A && git commit -m "feat: add example app with lyrics preview page"
```

---

### Task 7: 迁移测试（22 个）

**Files:**
- Create: `test/**`（镜像 `animation/ controllers/ layout/ models/ parsers/ renderers/`）

- [ ] **Step 1: 复制并重写 import**

```bash
mkdir -p "$DST/test"
cp -r "$SRC/test/widgets/apple_lyrics/." "$DST/test/"
find "$DST/test" -name "*.dart" -print0 | \
  xargs -0 sed -i "s#package:md3music/widgets/apple_lyrics/#package:flutter_amll/src/#g"
```

- [ ] **Step 2: 处理 SharedPreferences 依赖**

原测试用 `SharedPreferences.setMockInitialValues({})` + `LyricPreferences.instance.load()`。
包内 `load()` 现在读 `LyricPreferences.backend`（默认 no-op）。在测试顶部统一注入：

```dart
// test/support/amll_test_backend.dart
import 'package:flutter_amll/flutter_amll.dart';

/// 内存版偏好后端，供测试注入。
class MemoryLyricPreferencesBackend implements LyricPreferencesBackend {
  final Map<String, Object?> values = <String, Object?>{};

  @override double? getDouble(String key) => values[key] as double?;
  @override int? getInt(String key) => values[key] as int?;
  @override bool? getBool(String key) => values[key] as bool?;
  @override String? getString(String key) => values[key] as String?;
  @override Future<void> setDouble(String key, double v) async => values[key] = v;
  @override Future<void> setInt(String key, int v) async => values[key] = v;
  @override Future<void> setBool(String key, bool v) async => values[key] = v;
  @override Future<void> setString(String key, String v) async => values[key] = v;
}
```

对每个用到 `LyricPreferences` 的测试文件（7 处 import 中约 6 个），在 `setUp` 中加入：

```dart
setUp(() {
  LyricPreferences.backend = MemoryLyricPreferencesBackend();
});
```

- [ ] **Step 3: 跑测试**

Run: `cd "$DST" && flutter test`
Expected: 全部通过（22 个文件，与源仓库 `flutter test test/widgets/apple_lyrics` 结果一致）。

> 基线对照：先在源仓库跑 `cd "$SRC" && flutter test test/widgets/apple_lyrics` 记录通过数，迁移后必须完全一致（源仓库只读，跑测试不修改文件；若担心写 `.dart_tool`，可跳过基线直接以"全绿"为准）。

- [ ] **Step 4: 提交**

```bash
git add -A && git commit -m "test: migrate 22 lyric widget tests and add memory preferences backend"
```

---

### Task 8: 全量静态检查与清理

**Files:** 全仓库

- [ ] **Step 1: analyze**

Run: `cd "$DST" && flutter analyze`
Expected: `No issues found!`；若出现 `unused_import`（如 `apple_lyrics_view.dart` 的 `material_ui`），删除该 import 行后重跑。

- [ ] **Step 2: 确认零残留**

Run:
```bash
cd "$DST" && grep -rn "md3music\|package:md3music" lib test example --include="*.dart" --include="*.yaml" | grep -v "^example/lib/preview" || echo NO_HOST_REFS
```
Expected: `NO_HOST_REFS`（预览页注释中的历史说明可保留）

- [ ] **Step 3: 提交**

```bash
git add -A && git commit -m "chore: clean analyzer findings and host references"
```

---

### Task 9: 编写 README

**Files:**
- Create: `README.md`

内容结构（详见本计划第 2 节「README 大纲」）：
包定位 · 来源与迁移原则 · 目录结构 · 快速开始 · 公开 API · 可调选项总表 · 保留的优化点 · example 说明 · 宿主接入（md3music 回接指引） · 测试与验证 · 非目标。

- [ ] **Step 1: 写 README.md**（内容见第 2 节）
- [ ] **Step 2: 提交**

```bash
git add -A && git commit -m "docs: add README for flutter_amll"
```

---

### Task 10: 初始化版本库

- [ ] **Step 1: git init**

```bash
cd "$DST" && git init && git add -A && git status --short | head -40
```

- [ ] **Step 2: 首次提交**（若前面各 Task 未逐一提交，此处一次性提交）

```bash
git commit -m "feat: extract Apple Music style lyrics UI from md3music into flutter_amll"
```

---

## 2. README 大纲（Task 9 的填充内容）

```
# flutter_amll
一句话定位：Apple Music 风格（AMLL）逐字歌词渲染组件库，自 md3music AM 播放页完整抽取。

## 来源与迁移原则
- 源：private_md3music@rust-local-two 的 lib/widgets/apple_lyrics/**（20 文件 / 11,479 行）+ 22 个测试
- 原则：零逻辑改动。仅调整 import 路径、3 个宿主服务的类名与注入方式、1 处未使用 import
- 保留：全部渲染优化、全部可调选项（key 与默认值不变）

## 目录结构
lib/flutter_amll.dart（门面）· lib/src/{animation,controllers,layout,models,parsers,renderers,utils,platform,storage}
example/（预览调试页 demo）· test/（22 个测试）

## 快速开始
依赖声明 + 启动注入后端 + AppleLyricsView 最小用法（含 LyricParserChain.parse）

## 公开 API
AppleLyricsView / LyricLine / LyricParserChain / LyricPreferences / LyricPreferencesPanel /
LyricLayout / DuetLayout / Spring / LyricScrollController / LineScaleController /
AmllFrameDriver / AmllHaptics / AmllFontLoader / LyricPreferencesBackend

## 可调选项（LyricPreferences 全表：默认值 + 范围 + 作用）
## 组件参数（AppleLyricsView 13 项）
## 保留的优化点（清单）
## 宿主接入（md3music 回接：注入 backend / haptics / font picker；accentColor、BPM、positionListenable 用法）
## 测试与验证（flutter analyze / flutter test）
## 非目标与边界
```

---

## 3. 假设与待确认项（实施前请确认）

1. **包形态**：假设为 Flutter package（`publish_to: none`）+ `example/` demo app，而非独立可安装应用。
2. **包名**：假设 `flutter_amll`（与仓库目录同名），门面 `package:flutter_amll/flutter_amll.dart`。
3. **偏好 key 不变**：仍用 `lyric_font_size` 等原 key，便于后续 md3music 回接时用户设置无缝延续；若希望彻底隔离可加 `amll_` 前缀（需在 Task 4 一并改）。
4. **测试 import src**：测试直接 `import 'package:flutter_amll/src/renderers/...'`，需在 analysis_options 放开 `implementation_imports`（已包含）。
5. **本地环境**：已确认 Flutter 3.47.5 / Dart 3.13.4 可用；`flutter pub get` 需网络解析 `m3e_core` / `material_ui` / `xml` / `shared_preferences`。

---

## 4. 自检（Spec Coverage / Placeholder Scan / Type Consistency）

- **覆盖**：0.1~0.5 全部勘察结论 → Task 2/3/4/6/7 分别落实；优化与选项保留 → Task 2 零 diff 校验 + Task 4 key/常量 diff 校验；README → Task 9。
- **占位符**：无 TBD / "类似 Task N" / 无代码步骤；所有命令含预期输出。
- **类型一致性**：`AmllFrameDriver` / `AmllHaptics` / `AmllFontLoader` / `LyricPreferencesBackend` / `SharedPrefsLyricPreferencesBackend` / `MemoryLyricPreferencesBackend` 在 Task 3/4/6/7 中命名一致；`LyricPreferences.backend` 字段在 Task 4 定义、Task 6/7 使用。
