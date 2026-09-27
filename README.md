# flutter_amll

Apple Music 风格（AMLL）逐字歌词渲染组件库 —— 自 `md3music` 的 AM 风格播放页完整抽取，保留全部渲染优化与可调节选项，且不依赖任何宿主业务代码。

> **当前状态**：抽取已完成。19 个源文件 + 4 个平台注入点 + 1 个存储后端迁入 `lib/src/`，22 个测试全部通过（402/402），`flutter analyze` 全仓库 `No issues found!`。
>
> **源仓库**：`private_md3music@rust-local-two`（v5.7.0+45）的 `lib/widgets/apple_lyrics/**` —— 20 个源文件 / 11,479 行，外加 `test/widgets/apple_lyrics/**` 22 个测试。**抽取过程对源仓库只读，未做任何修改。**方案与逐 Task 记录见 [`docs/superpowers/plans/2026-09-28-amll-lyrics-extraction.md`](docs/superpowers/plans/2026-09-28-amll-lyrics-extraction.md)。
>
> **迁移原则**：零逻辑改动。除 import 路径、4 个宿主平台服务降级为注入点、偏好存储收口为可注入后端外，渲染/动画/解析代码逐行保持原样。

---

## 目录结构

```
flutter_amll/
├── lib/
│   ├── flutter_amll.dart          # 公开 API 门面（唯一推荐导入入口）
│   └── src/
│       ├── apple_lyrics_view.dart # AppleLyricsView 主组件（3376 行）
│       ├── animation/spring.dart  # 弹簧物理引擎（临界/欠/过阻尼解析解）
│       ├── controllers/           # lyric_scroll_controller / line_scale_controller
│       ├── layout/                # lyric_layout / duet_layout / lyric_preferences(_panel)
│       ├── models/lyric_line.dart # LyricLine / LyricWord 统一歌词模型
│       ├── parsers/               # krc / lrc / ttml / plaintext + lyric_parser_chain
│       ├── renderers/             # word_renderer / line_renderer / emphasize_effect / interlude_dots
│       ├── utils/lyric_position.dart
│       ├── platform/              # frame_driver / haptics / font_loader / toast（4 个宿主注入点）
│       └── storage/lyric_preferences_backend.dart
├── example/                       # demo app：歌词预览调试页
└── test/                          # 22 个测试（与源仓库一一对应）
```

依赖：`flutter`、`m3e_core ^1.1.4`、`material_ui ^1.3.0`、`shared_preferences ^2.5.0`、`xml ^6.5.0`（TTML）。
环境：Dart `^3.12.0`，Flutter `>=3.47.0`（`material_ui` 1.3.0 实际要求 3.47+）。

---

## 快速开始

### 1. 声明依赖

```yaml
dependencies:
  flutter_amll:
    path: ../flutter_amll   # 或 git:
```

### 2. 启动时注入偏好后端

`LyricPreferences` 默认后端为空实现（读写 no-op），宿主需在 app 启动处注入一次，否则偏好不会持久化：

```dart
import 'package:flutter_amll/flutter_amll.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  LyricPreferences.backend = SharedPrefsLyricPreferencesBackend(prefs);
  await LyricPreferences.instance.load();
  runApp(const MyApp());
}
```

### 3. 渲染歌词

```dart
import 'package:flutter_amll/flutter_amll.dart';

final List<LyricLine> lines = LyricParserChain.parse(rawLyricText);

AppleLyricsView(
  lines: lines,
  currentTimeMs: 0,
  // 推荐：让组件内部订阅高频 position，避免父级每 200ms 重建组件树
  positionListenable: playerProvider.positionNotifier,
  adaptTimeMs: (raw) => raw.inMilliseconds - offsetMs,
  isPlaying: playerProvider.isPlaying,
  playbackNotReady: playerProvider.isPlaybackNotReady,
  forceDarkBackground: true,        // AM 深色背景：强制白色歌词
  enableInterludeDots: hasWordTiming, // LRC 无逐字时间戳时建议关闭
  doubleTapToJump: true,
  accentColor: artworkAccentColor,  // 配合 useDynamicLyricColor 混色
  songBpm: song.bpm,                // 辉光阈值按快慢歌区分
  onSeek: (ms) => player.seek(Duration(milliseconds: ms)),
);
```

解析与渲染分离：调用方负责 `LyricParserChain.parse`（自动识别 KRC / LRC / TTML / 纯文本），组件只接收已解析的 `List<LyricLine>`。

---

## 公开 API

`import 'package:flutter_amll/flutter_amll.dart';`

| 导出 | 说明 |
|---|---|
| `AppleLyricsView` | 歌词主组件（`StatefulWidget`，CustomPainter 绘制） |
| `LyricLine` / `LyricWord` | 统一歌词模型（支持逐字时间戳、翻译、罗马音、对唱 agentId） |
| `LyricParserChain` | 解析器链，`parse` / `detectFormat` |
| `KrcParser` `LrcParser` `TtmlParser` `PlaintextParser` | 单一格式解析器 |
| `LyricPreferences` | 全部显示偏好（ChangeNotifier，全局单例） |
| `LyricPreferencesPanel` | 偏好设置面板 UI（字号/间距/字重/模糊/辉光等滑块） |
| `LyricLayout` / `DuetLayout` | 行布局计算 / 对唱（TTML agentId）布局 |
| `Spring` | 弹簧动画引擎 |
| `LyricScrollController` / `LineScaleController` | 滚动与逐行缩放弹簧控制器 |
| `AmllFrameDriver` | 60fps 共享帧驱动（eco 限帧） |
| `AmllHaptics` / `AmllToast` / `AmllFontLoader` | 触觉 / 轻提示 / 字体选择三个宿主注入点 |
| `LyricPreferencesBackend` | 偏好持久化后端接口 + 内存 / SharedPreferences 两种实现 |
| `adjustLyricPosition` | 播放位置 → 歌词位置的时间偏移映射 |

`renderers/*` 为内部实现，不对外导出；测试与自定义扩展可直接 `import 'package:flutter_amll/src/renderers/word_renderer.dart';`。

---

## 可调节选项

### `LyricPreferences`（持久化于 SharedPreferences，key 沿用原名）

| 选项 | 默认 | 范围 / 取值 | 作用 |
|---|---|---|---|
| `fontSize` | 手机 29 / Pad 40 | 12 ~ 50 px | 歌词字号 |
| `lineSpacing` | 手机 1.4 / Pad 0.9 | 0.5 ~ 2.0 | 行间距系数；实际行高 = `(fontSize / 15) * lineSpacing` |
| `fontWeightValue` | 手机 600 / Pad 900 | 300 ~ 900 | 字重（FontWeight.value） |
| `useGaussianBlur` | `false` | bool | 非当前行高斯模糊（AM 模糊层） |
| `blurIntensity` | `1.0` | 0.5 ~ 2.0 | 模糊强度倍数（sigma = 距离分级 × 本值） |
| `useGlowEffect` | `true` | bool | 当前行辉光强调 |
| `useFlowingBackground` | `false` | bool | 流动背景 |
| `useDuetLayout` | `false` | bool | 对唱布局（按 TTML agentId 左右分列） |
| `showTranslation` | `true` | bool | 是否显示副行 |
| `displayMode` | `translation` | `translation` / `roma` | 副行显示翻译还是罗马音 |
| `fontSource` | `system` | `system` / `bundled`(废弃) / `custom` | 歌词字体来源 |
| `customFontPath` | `null` | 路径字符串 | 自定义 TTF/OTF 文件路径 |
| `ecoMode` | `true` | bool | 歌词界面锁定 60fps（滑动时临时解锁） |
| `useDynamicLyricColor` | `true` | bool | 当前行按「70% 白 + 30% 封面提取色」混色 |
| `glowThresholdFactor` | `1.2` | 1.0 ~ 2.0 | 辉光触发阈值 = 字长中位数 × 本系数 |
| `inactiveScale` | `0.850` | 0.80 ~ 1.00（40 档） | 非当前行缩放（清晰层与模糊层共用，保证重合） |
| `alignPosition` | `0.35` | 0.15 ~ 0.65（50 档） | 当前行中心在视口高度的比例位置 |
| `cascadeMaxDelayMs` | `750` | 100 ~ 2000 ms | 级联错峰最大延迟 |
| `cascadeBaseStepMs` | `60` | 20 ~ 200 ms | 级联错峰相邻行步长 |
| `cascadeDecayX` | `1.1` | 1.0 ~ 2.0 | 级联衰减分母（每越过一行步长 × 1/x） |
| `liftHeightPx` | `3.0` | 0 ~ 10 px | 已播字上浮高度 |
| `staggerFromCurrentLine` | `true` | bool | 错峰起点：当前行（`true`）/ 视口顶部（历史行为） |

持久化 key：`lyric_font_size` `lyric_line_spacing` `lyric_font_weight` `lyric_use_gaussian_blur` `lyric_blur_intensity` `lyric_use_glow_effect` `lyric_use_flowing_background` `lyric_font_source` `lyric_custom_font_path` `lyric_show_translation` `lyric_display_mode` `lyric_use_duet_layout` `lyric_eco_mode` `lyric_dynamic_color` `lyric_glow_threshold_factor` `lyric_inactive_scale` `lyric_align_position` `lyric_cascade_max_delay_ms` `lyric_cascade_base_step_ms` `lyric_cascade_decay_x` `lyric_lift_height_px` `lyric_stagger_from_current`。

### `AppleLyricsView` 构造参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `lines` | 必填 | 已解析的歌词行（按 startTime 升序） |
| `currentTimeMs` | 必填 | 当前播放时间（ms）；使用 `positionListenable` 时传 0 |
| `isPlaying` | `false` | 播放中 |
| `playbackNotReady` | `false` | 切歌 loading / 缓冲期：冻结逐字动画时钟，避免字内渐变抽搐 |
| `onSeek` | `null` | 点击行回调（宿主执行 seek） |
| `enableScale` | `true` | 行的进/离场缩放弹簧 |
| `forceDarkBackground` | `false` | 强制白色歌词（AM 深色背景恒为 true） |
| `enableInterludeDots` | `true` | 行间节奏点动画（LRC 无逐字时间戳建议关闭） |
| `doubleTapToJump` | `false` | 双击才跳转（开启后单击不跳转） |
| `accentColor` | `null` | 封面提取色，供动态字体颜色混色 |
| `songBpm` | `null` | BPM ≥100 视为快歌（辉光阈值 500ms），否则 1000ms |
| `positionListenable` | `null` | 高频位置源，由组件内部订阅（性能解耦） |
| `adaptTimeMs` | `null` | 位置二次校正（如在线歌词时间偏移） |

---

## 保留的渲染优化

迁移为等价复制，以下优化全部原样保留：

- **逐字 mask 渲染** + 无逐字时间戳时**整行降级渲染**
- **Ticker 驱动**（非 `DateTime.now()`），保证 `pump(Duration)` 可推进弹簧、测试可验证动画
- **二分查找**当前行（O(log N)）
- **eco 60fps 共享节拍**：与封面旋转/频谱共用 `AmllFrameDriver`，消除 120Hz 屏上双定时器交错导致的 115~120fps
- **模糊层脏标记缓存**：稳态逐字演唱时模糊层不重建 widget 树
- **每帧重绘阈值**（位移 >0.5px、透明度 >0.001）低于感知下限，跳过无效重绘
- **`positionListenable` 内部订阅**：脱离父级 200ms 重建路径；暂停时 `isPlaying` 仍由宿主低频通知更新，避免 Ticker 不收敛
- **`playbackNotReady` 时钟冻结**：避免「帧时钟前进 → 兜底回吸」锯齿循环
- **辉光阈值自适应**：BPM 优先，回落字长中位数统计
- **间奏行节奏点**、**对唱（duet）布局**、**已播字上浮**、**级联错峰**
- **动态字体颜色**、**Pad/手机差异化默认值**（最短边 ≥600dp 判为 Pad）

---

## 宿主接入点

包内不含任何业务耦合，宿主通过三个注入点接回自有能力：

```dart
// 1. 偏好持久化（默认是内存后端，不注入就不会落盘，且静默无提示）
LyricPreferences.backend = SharedPrefsLyricPreferencesBackend(prefs);

// 2. 触觉反馈（默认 HapticFeedback.selectionClick；md3music 走原生 VibratorManager）
AmllHaptics.tick = AppHaptics.tick;

// 3. 轻提示（默认空操作；md3music 走 fluttertoast）
AmllToast.show = (msg, {long = false}) => showToast(msg, long: long);

// 4. 字体文件选择（依赖原生 SAF 通道，包内无法提供，默认返回 null）
AmllFontLoader.pickFontFile = CustomFontLoader.pickFontFile;
```

> 四个注入点的默认值都是"安全但不完整"的实现：偏好不落盘、触觉走 Flutter 内置、
> Toast 静默、字体选择返回 null。**宿主不注入不会崩溃，但对应能力不会生效**，
> 接入时请按上面四行逐一接回自有实现。

`md3music` 回接时，`full_player_am.dart` 的歌词区可替换为：

```dart
RepaintBoundary(
  child: AppleLyricsView(
    lines: _parsedLyrics,
    currentTimeMs: 0,
    positionListenable: playerProvider.positionNotifier,
    adaptTimeMs: (raw) { /* 在线歌词偏移 */ },
    isPlaying: playerProvider.isPlaying,
    playbackNotReady: playerProvider.isPlaybackNotReady,
    forceDarkBackground: true,
    enableInterludeDots: !isLocalLrcLyricWithoutWordTiming(song),
    doubleTapToJump: lyricDoubleTap,
    accentColor: _lyricAccentColor,
    songBpm: song?.bpm,
    onSeek: (ms) => playerProvider.seek(Duration(milliseconds: ms)),
  ),
)
```

配合 `RepaintBoundary` 隔离每帧重绘范围，避免父级 `TabBarView` 被牵连重建。

---

## Example

`example/` 是原仓库的歌词预览调试页，不依赖 `just_audio` 与任何网络/业务 Provider：

- 文本框可直接粘贴 KRC / LRC 原文并即时渲染
- 顶部菜单一键加载内置 KRC / LRC 示例数据
- 时间滑块（0~60s）模拟播放进度，"播放/暂停"每帧 +16ms 自动推进
- AppBar 入口打开 `LyricPreferencesPanel`，实时调节上述全部选项

```bash
cd example && flutter pub get && flutter run
```

---

## 测试与验证

```bash
flutter pub get
flutter analyze          # No issues found!
flutter test             # 402 / 402 passed
cd example && flutter pub get && flutter analyze   # No issues found!
```

测试覆盖：弹簧求解、逐字/整行渲染器、辉光强调、间奏点、四种解析器、布局（副行翻转 / inactiveScale / 模糊强度）、滚动控制器、偏好细节参数、位置解耦。

测试侧已与 `shared_preferences` 完全解耦：统一在 `setUp` 中调用 `LyricPreferences.resetForTest()`
并注入 `MemoryLyricPreferencesBackend`，通过 `values` 快照断言落盘内容。

---

## 非目标与边界

- 不含 MD3 风格歌词（`Md3LyricPreferences`）与桌面歌词/锁屏歌词服务
- 不含播放器页面本身（`full_player_am.dart`）、评论、封面、频谱等宿主 UI
- 不含网络取词与本地歌词读取——解析输入由调用方提供
- 迁移期不做视觉/逻辑重构、不重命名字段、不变更默认值与持久化 key
- 源码中保留了源仓库的两处既有写法以保持行为不变：`TickerMode.of`（Flutter 3.35 后废弃，
  替代 API `valuesOf` 返回 record、语义不同，暂不迁移）与 `_tryLoadCustomFont` 内的 `print`
  调试输出；两者以行内 `ignore` 注释消除 analyzer 告警，未改调用方式
- 使用 `dart:io`（自定义字体文件读取），因此不支持 Web 平台

## License

沿用源项目 `md3music` 的许可（AGPL-3.0）；抽取代码版权归原作者所有。
