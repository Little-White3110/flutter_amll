# flutter_amll

Apple Music 风格（AMLL）逐字歌词渲染组件库 —— 自 `md3music` 的 AM 风格播放页完整抽取，保留全部渲染优化与可调节选项，且不依赖任何宿主业务代码。

> **当前状态**：已对齐源仓库 HEAD（`b197388f`，2026-11-15）。39 个源文件 + 平台注入点 + 存储后端 + 设置面板 / 预览页迁入 `lib/src/`；**57 个测试文件 / 764 个用例全部通过**，`flutter analyze`（lib / test / example）均 `No issues found!`。
>
> **源仓库**：`private_md3music@rust-local-two` 的 `lib/widgets/apple_lyrics/**` —— 26 个源文件 / 18,706 行，外加 `test/widgets/apple_lyrics/**` 52 个测试。**抽取过程对源仓库只读，未做任何修改。**
>
> **迁移原则**：零逻辑改动。除 import 路径、宿主平台服务降级为注入点、偏好存储收口为可注入后端、以及 UI 页面依赖链（RemoteSlider / 上下文菜单 / 颜色选择器）改为组件库内等价实现外，渲染 / 动画 / 解析代码逐行保持原样。源仓库 4 项架构级性能重构（模糊层画布合成、文字层两层分层、主行 P1-2/P1-3 预栅格、副行翻转期预栅格）与其后全部行为修正已一并对齐。

---

## 目录结构

```
flutter_amll/
├── lib/
│   ├── flutter_amll.dart          # 公开 API 门面（唯一推荐导入入口）
│   └── src/
│       ├── apple_lyrics_view.dart # AppleLyricsView 主组件（6032 行，与源 HEAD 同源）
│       ├── animation/spring.dart  # 弹簧物理引擎（临界/欠/过阻尼解析解）
│       ├── controllers/           # lyric_scroll_controller / line_scale_controller
│       ├── layout/                # lyric_layout / duet_layout / lyric_preferences(_panel)
│       │                          # + aux_scope / animation_preset_store
│       │                          # + color_setting_tile / seed_color_picker
│       ├── models/                # lyric_line / aux_text_image
│       ├── parsers/               # krc / lrc / ttml / plaintext + lyric_parser_chain
│       ├── preview/               # lyrics_preview_page（组件库内置调试页）
│       ├── renderers/             # word / line / emphasize_effect / interlude_dots / sweep_fill
│       ├── utils/                 # position / line_balance / wrap_plan / credit_filter
│       │                          # + line_color / hex_color
│       ├── platform/              # build_flags / frame_driver / haptics / font_loader
│       │                          # + toast / remote_slider / app_text_context_menu
│       └── storage/lyric_preferences_backend.dart
├── example/                       # demo app：直接挂载组件库内置预览页
└── test/                          # 57 个测试文件 / 764 用例（与源仓库一一对应）
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
| `LyricPreferencesPanel` | 偏好设置面板 UI（字号/字重/行距滑块 + 字体来源 + 自定义颜色） |
| `LyricsPreviewPage` | 歌词渲染预览调试页（KRC/LRC 输入、时间轴、播放模拟、面板入口） |
| `LyricColorSettingTile` / `SeedColorPicker` | 自定义歌词颜色入口与 HSV 色轮 / 色号选择器 |
| `LyricLayout` / `DuetLayout` | 行布局计算 / 对唱（TTML agentId）布局 |
| `Spring` | 弹簧动画引擎 |
| `LyricScrollController` / `LineScaleController` | 滚动与逐行缩放弹簧控制器 |
| `AmllFrameDriver` | 60fps 共享帧驱动（eco 限帧） |
| `AmllHaptics` / `AmllToast` / `AmllFontLoader` / `AmllRemoteControl` | 触觉 / 轻提示 / 字体选择 / 遥控模式四个宿主注入点 |
| `RemoteSlider` / `buildAppTextContextMenu` | TV 方向键安全滑块 / 输入框中文上下文菜单（组件库内实现） |
| `parseHexColor` / `formatHexColor` | 十六进制色号解析与格式化 |
| `LyricPreferencesBackend` | 偏好持久化后端接口 + 内存 / SharedPreferences 两种实现 |
| `adjustLyricPosition` | 播放位置 → 歌词位置的时间偏移映射 |

`renderers/*` 为内部实现，不对外导出；测试与自定义扩展可直接 `import 'package:flutter_amll/src/renderers/word_renderer.dart';`。

---

## 可调节选项

### `LyricPreferences`（经 `backend` 持久化，key 沿用原名）

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
| `lineBalance` | `true` | bool | 平衡行换行：长行用 DP 求均衡断点，关闭则退回旧贪心 |
| `showTranslation` | `true` | bool | 是否显示副行 |
| `displayMode` | `translation` | `translation` / `roma` | 副行显示翻译还是罗马音 |
| `fontSource` | `system` | `system` / `bundled`(废弃) / `custom` | 歌词字体来源 |
| `customFontPath` | `null` | 路径字符串 | 自定义 TTF/OTF 文件路径 |
| `ecoMode` | 移动端高刷 `true`，其余 `false` | bool | 歌词界面锁定 60fps；`_defaultEcoMode()` 按平台 + 刷新率自适应，桌面/测试宿主保持关闭 |
| `useDynamicLyricColor` | `true` | bool | 当前行按「70% 白 + 30% 封面提取色」混色 |
| `fillMode` | `sweep` | `classic` / `sweep` | 字内渐变模型：扫光（墨迹推进 + 自适应羽化）/ 原宽过渡带 |
| `glowIntensity` | `1.0` | 0.2 ~ 2.0 | 辉光强度倍数（只调亮度；>1.0 走加法叠加，不改光形） |
| `useGlowCharScale` | `true` | bool | 辉光字符缩放：关闭只停放大与左右外扩，保留上浮/浮层/辉光 |
| `glowThresholdMode` | `fixed` | `adaptive` / `fixed` | 辉光触发判定：固定时长 / 按 BPM·字长自适应 |
| `glowFixedThresholdMs` | `1000` | 500 ~ 2000 ms | 固定时长判定阈值（仅 fixed 生效） |
| `glowThresholdFactor` | `1.2` | 1.0 ~ 2.0 | 自适应判定：触发阈值 = 字长中位数 × 本系数 |
| `inactiveScale` | `0.850` | 0.80 ~ 1.00（40 档） | 非当前行缩放（清晰层与模糊层共用，保证重合） |
| `alignPosition` | `0.35` | 0.15 ~ 0.65（50 档） | 当前行中心在视口高度的比例位置 |
| `cascadeMaxDelayMs` | `750` | 100 ~ 2000 ms | 级联错峰最大延迟 |
| `cascadeBaseStepMs` | `60` | 20 ~ 200 ms | 级联错峰相邻行步长 |
| `cascadeDecayX` | `1.1` | 1.0 ~ 2.0 | 级联衰减分母（每越过一行步长 × 1/x） |
| `liftHeightPx` | `3.0` | 0 ~ 10 px | 已播字上浮高度 |
| `staggerFromCurrentLine` | `true` | bool | 错峰起点：当前行（`true`）/ 视口顶部（历史行为） |

**本轮同步新增的选项**（详见源码注释；带 `*` 的范围在 Windows 平台另有差异化实调值，
见 `LyricPreferences.*ForCurrentPlatform`）：

| 选项 | 默认 | 范围 / 取值 | 作用 |
|---|---|---|---|
| `lyricPosition` | `left` | `left` / `center` / `right` | 歌词整体水平位置；与对唱布局互斥，对唱开启时逐行对齐接管 |
| `softEdgeAntiAlias` | `false` | bool | 字体柔边抗锯齿：`MaskFilter.blur` 极小半径柔化字形边缘，字形图烘焙同步留 3σ pad |
| `auxScope` | `translation` | 字段式枚举 | 副行显示范围（翻译 / 罗马音 / 两者等） |
| `hideLyricCredits` | `false` | bool | 过滤在线歌词头部的作词/作曲/编曲等元信息块 |
| `playedOpacity` / `unplayedOpacity` | 平台默认* | 平台范围* | 已播 / 未播歌词透明度，分别作用于清晰层与模糊层 |
| `dynamicColorMixRatio` | `0.15`* | 0.0 ~ 1.0（Windows 上限 0.30）* | 当前行已播色与封面提取色的混色比例 |
| `useAboveLinesPlayedColor` | `false`* | bool | 当前行上方行是否也用「已播色」着色（合成期 `ColorFilter`，不重烘焙模糊图） |
| `blurLevelCrossfade` / `blurLevelFadeMs` | 平台默认* | bool / ms | 切行时模糊等级渐变切换开关与时长 |
| `earlyLineSwitch` / `preStartBiasMs` | 平台默认* | bool / ms | 提前换行动画开关与预启动提前量微调 |
| `entryBlurFadeMs` | 平台默认* | ms | 入场模糊淡出时长 |
| `cascadeStepDecay` | 平台默认* | 系数 | 级联错峰步长衰减 |
| `interludeDotsStartX` / `interludeDotRadius` / `interludeDotSpacing` | 平台默认* | × 字号 | 间奏点水平起点、半径、间距的自定义参数 |

持久化 key：`lyric_font_size` `lyric_line_spacing` `lyric_font_weight` `lyric_use_gaussian_blur` `lyric_blur_intensity` `lyric_blur_level_crossfade` `lyric_blur_level_fade_ms` `lyric_entry_blur_fade_ms` `lyric_early_line_switch` `lyric_use_glow_effect` `lyric_glow_intensity` `lyric_glow_char_scale` `lyric_soft_edge_antialias` `lyric_use_flowing_background` `lyric_use_duet_layout` `lyric_position` `lyric_line_balance` `lyric_show_translation` `lyric_display_mode` `lyric_aux_scope` `lyric_hide_credits` `lyric_credit_pattern` `lyric_font_source` `lyric_custom_font_path` `lyric_custom_text_color` `lyric_eco_mode` `lyric_dynamic_color` `lyric_dynamic_color_mix_ratio` `lyric_above_lines_played_color` `lyric_played_opacity` `lyric_unplayed_opacity` `lyric_glow_threshold_factor` `lyric_glow_threshold_mode` `lyric_glow_fixed_threshold_ms` `lyric_fill_mode` `lyric_inactive_scale` `lyric_align_position` `lyric_cascade_max_delay_ms` `lyric_cascade_base_step_ms` `lyric_cascade_decay_x` `lyric_prestart_bias_ms` `lyric_lift_height_px` `lyric_stagger_from_current` `lyric_interlude_dots_start_x` `lyric_interlude_dot_radius` `lyric_interlude_dot_spacing`。

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
- **平衡行换行**：长行断点由 `LyricWrapPlanner`（DP 最优化，移植 AMLL `calcBalancedBreaks`）统一产出，行高测量 / 逐字绘制 / 整行绘制 / 模糊层四处消费同一份计划，消除「第二行只剩两三个字」并结构性杜绝测量与绘制行数不一致导致的重叠
- **扫光（sweep）字内渐变**：前端沿「墨迹长度」推进（字间空白瞬时跨越），羽化宽度按字宽 + 时长自适应；`classic` 为原「行内累计宽度 maskX + 固定过渡半宽」模型，二者由 `fillMode` 二选一
- **辉光三层剖面**：紧 / 中 / 松三层高斯叠加（字形最亮、向外单调递减，不挖空字形），2× 超采样烘焙精灵、绘制期 `ColorFilter` 上色（换色不重烘焙），并按字数内进度前沿逐段点亮
- **动态字体颜色**、**Pad/手机/Windows 差异化默认值**（最短边 ≥600dp 判为 Pad；Windows 便携版另有实调范围与中轴值）
- **Windows 整词字形图**：3× 超采样预栅格整词白字图 + `FilterQuality.low` 双线性缩回，消除上浮动画的整像素台阶；行盒变化自动重烘焙
- **歌词位置（左/中/右）**：与对唱布局互斥，逐行对齐真值源统一供文字层、模糊层与缩放锚点消费
- **柔边抗锯齿**：`LyricLayout.paintStyle` 统一注入 `MaskFilter.blur`，关闭时逐像素零回归
- **动画预设管理**：`LyricAnimationPresetStore` 支持 18 项动画参数导入/导出（含内置「性能优先 / 流畅优先」预设）
- **歌词头部信息过滤**、**副行显示范围**、**已播/未播透明度**、**提前换行与模糊等级渐变切换**、**间奏点自定义参数**
- **模糊层画布合成**：模糊层从 widget 树重构为单一 painter 直接读实时图 Map，切行只 `fireRepaint()` 不重建树；主行与副行模糊图共用 16ms 帧预算烘焙队列，异步 `toImage` 带令牌 / 几何签名保护，切歌统一释放 GPU 图片
- **文字层两层分层**：当前行单独一层逐字重绘，其余行走静态层，稳态演唱时非当前行零重绘
- **主行 / 副行预栅格**：P1-2 非当前行预栅格化、P1-3 渐变优化；副行翻转期改用预热好的位图绘制（进度动画 0→1 / 1→0 不触发重烘焙）
- **级联错峰统一轮次**：预启动与回落共用同一轮次，修正预启动窗口内行被跳过、副行过渡与级联释放速度突变，并优化清晰层 / 模糊层淡入淡出

---

## 宿主接入点

包内不含任何业务耦合，宿主通过以下注入点接回自有能力：

```dart
// 1. 偏好持久化（默认是内存后端，不注入就不会落盘，且静默无提示）
LyricPreferences.backend = SharedPrefsLyricPreferencesBackend(prefs);

// 2. 触觉反馈（默认 HapticFeedback.selectionClick；md3music 走原生 VibratorManager）
AmllHaptics.tick = AppHaptics.tick;

// 3. 轻提示（默认空操作；md3music 走 fluttertoast）
AmllToast.show = (msg, {long = false}) => showToast(msg, long: long);

// 4. 字体文件选择（依赖原生 SAF 通道，包内无法提供，默认返回 null）
AmllFontLoader.pickFontFile = CustomFontLoader.pickFontFile;

// 5. Windows 内置字体 family（宿主注册思源黑体后写入；默认 null = 系统字体链）
AmllFontLoader.windowsDefaultFamily = WindowsDefaultFont.loadedFamily;

// 6. 遥控模式 / D-pad 导航开关（TV 构建恒走 directional，不受本开关影响）
AmllRemoteControl.enabled = remoteControlProvider.enabled;
```

> 注入点的默认值都是"安全但不完整"的实现：偏好不落盘、触觉走 Flutter 内置、
> Toast 静默、字体选择返回 null、遥控模式关闭。**宿主不注入不会崩溃，但对应能力不会生效**，
> 接入时请按上面几行逐一接回自有实现。

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

`example/` 直接挂载组件库内置的 `LyricsPreviewPage`（`lib/src/preview/`），
不依赖 `just_audio` 与任何网络/业务 Provider。预览页本体已随本轮移植纳入包内，
宿主 App 也可直接 `import 'package:flutter_amll/flutter_amll.dart'` 使用：

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
flutter test             # 764 / 764 passed
cd example && flutter pub get && flutter analyze   # No issues found!
```

测试覆盖：弹簧求解、逐字 / 整行渲染器、扫光与三层辉光、柔边抗锯齿、Windows 字形图、副行预栅格、模糊画布合成与烘焙队列、级联错峰、间奏点、四种解析器、布局（副行翻转 / inactiveScale / 模糊强度）、动画预设、滚动控制器、偏好细节参数、位置解耦、设置面板与预览页。

测试侧已与 `shared_preferences` 完全解耦：统一在 `setUp` 中调用 `LyricPreferences.resetForTest()`
并注入 `MemoryLyricPreferencesBackend`，通过 `values` 快照断言落盘内容。

---

## 非目标与边界

- 不含宿主设置页容器与其搜索索引注册（属宿主 App 层；面板本体已在包内）
- 不含 MD 风格歌词（`Md3LyricPreferences` / `lyrics_view.dart`）与桌面歌词/锁屏歌词服务
- 不含播放器页面本身（`full_player_am.dart`）、评论、封面、频谱等宿主 UI
- 不含网络取词与本地歌词读取——解析输入由调用方提供
- 迁移期不做视觉/逻辑重构、不重命名字段、不变更持久化 key；源仓库的产品级默认值翻转未跟进
  （`useGlowEffect` / `lineBalance` / `useDynamicLyricColor` 保持本库既有默认 `true`），
  `ecoMode` 例外：跟随上游新增的按平台 / 刷新率自适应默认
- 源码中保留了源仓库的两处既有写法以保持行为不变：`TickerMode.of`（Flutter 3.35 后废弃，
  替代 API `valuesOf` 返回 record、语义不同，暂不迁移）与 `_tryLoadCustomFont` 内的 `print`
  调试输出；两者以行内 `ignore` 注释消除 analyzer 告警，未改调用方式
- 使用 `dart:io`（自定义字体文件读取），因此不支持 Web 平台

## License

沿用源项目 `md3music` 的许可（AGPL-3.0）；抽取代码版权归原作者所有。
