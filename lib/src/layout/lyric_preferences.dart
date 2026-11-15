import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../storage/lyric_preferences_backend.dart';

/// 歌词字体来源枚举（与全局 [FontSource] 解耦，允许歌词使用与 UI 不同的字体）。
///
/// - [LyricFontSource.system]：使用手机系统字体（默认，符合"优先展示用户手机字体"需求）
/// - [LyricFontSource.bundled]：已废弃（内置 SimHei 已移除，仅保留枚举值以稳定
///   `fontSource.index` 的原生契约 0=system 1=bundled 2=custom），行为等同 system
/// - [LyricFontSource.custom]：使用用户通过 SAF 选择的 TTF/OTF 文件
enum LyricFontSource { system, bundled, custom }

/// 歌词辅助行显示模式：翻译 or 罗马音。
///
/// - [LyricDisplayMode.translation]：显示中文翻译（默认）
/// - [LyricDisplayMode.roma]：显示罗马音/音译
///
/// 仅当 [LyricPreferences.showTranslation] 为 true 时副行才显示，
/// [displayMode] 决定显示哪个字段。
enum LyricDisplayMode { translation, roma }

/// 字内渐变（当前行扫光）模型：classic = 原有宽过渡带；sweep = 移植自 myune 的扫光。
///
/// - [LyricFillMode.classic]：原有「行内累计宽度 maskX + 固定过渡半宽（行内平均字宽）」
///   模型，过渡带宽、边缘柔和。
/// - [LyricFillMode.sweep]：myune 扫光模型——前端沿**墨迹长度**推进（字间空白瞬时跨越），
///   羽化宽度按字宽 + 时长自适应（快字宽、慢字窄），过渡带更锐利（默认）。
///
/// 与 [LyricFontSource] / [LyricDisplayMode] 一样，持久化时存 `name`，未知值回退默认。
enum LyricFillMode { classic, sweep }

/// 辉光触发判定模式：自适应 or 固定时长。
///
/// - [GlowThresholdMode.adaptive]：原有判定——按歌曲 BPM / KRC 歌词字长中位数
///   × 阈值系数（[LyricPreferences.glowThresholdFactor]）自适应推断触发阈值。
/// - [GlowThresholdMode.fixed]：固定时长判定——字时长 >= 固定阈值
///   （[LyricPreferences.glowFixedThresholdMs]，默认 1000ms）才触发辉光（默认）。
///
/// 与 [LyricFillMode] 一样，持久化时存 `name`，未知值回退默认。
enum GlowThresholdMode { adaptive, fixed }

/// 歌词显示偏好设置（字号 + 行间距 + 字体）。
///
/// 提供全局静态访问 + ChangeNotifier 通知，供 AppleLyricsView、
/// 设置页滑块、长按菜单共同读写。
///
/// 偏好通过 [LyricPreferencesBackend]（[backend]）持久化，默认内存实现；
/// 宿主可注入自有后端以落盘。
///
/// 字号范围：[minFontSize] ~ [maxFontSize]，默认 [defaultFontSize]。
/// 行间距系数范围：[minLineSpacing] ~ [maxLineSpacing]，默认 [defaultLineSpacing]。
/// 实际行高 = (fontSize / defaultFontSize) * lineSpacing。
///
/// 字体来源（[fontSource]）独立于全局 ThemeProvider，允许歌词使用专属字体。
/// 自定义字体通过 Flutter [FontLoader] 动态注册，family 名固定为
/// [lyricCustomFontFamily]；切换为 system/bundled 时该 family 不会被使用。
class LyricPreferences extends ChangeNotifier {
  LyricPreferences._();
  static final LyricPreferences instance = LyricPreferences._();

  /// 持久化后端。默认内存实现（读写仅在当前进程有效，不落盘）。
  ///
  /// 宿主 app 启动时注入 [SharedPrefsLyricPreferencesBackend] 即可持久化：
  /// ```dart
  /// LyricPreferences.backend = SharedPrefsLyricPreferencesBackend(prefs);
  /// ```
  static LyricPreferencesBackend backend = MemoryLyricPreferencesBackend();

  /// 歌词自定义字体注册到 Flutter 的 family 名（固定）
  static const String lyricCustomFontFamily = 'LyricUserCustomFont';

  // ============== 范围与默认值 ==============

  /// 字号最小值（px）
  static const double minFontSize = 12;

  /// 字号最大值（px）
  static const double maxFontSize = 50;

  /// 字号默认值（px）
  ///
  /// 这是公式 `(fontSize / defaultFontSize) * lineSpacing` 中的分母，
  /// 保持 15px 不变。改动此值会影响所有用户计算出的实际行高。
  static const double defaultFontSize = 15;

  /// 用户首选项的字号默认值（px）
  ///
  /// 新用户首次进入时歌词显示的字号。保持 22px 让初始实际行高为
  /// (22/15)*1.5 = 2.20×，更符合阅读习惯。
  static const double defaultUserFontSize = 22;

  /// 行间距系数最小值
  ///
  /// 下限 0.5 允许把行间距压到比默认行高更紧（0.5×），用于紧凑排版偏好。
  static const double minLineSpacing = 0.5;

  /// 行间距系数最大值
  static const double maxLineSpacing = 2.0;

  /// 行间距系数默认值
  static const double defaultLineSpacing = 1.5;

  /// 字重最小值（FontWeight.value，细体）
  static const int minFontWeight = 300;

  /// 字重最大值（FontWeight.value，黑体）
  static const int maxFontWeight = 900;

  /// 字重默认值（FontWeight.value，常规）
  ///
  /// 与当前未设置字重时的渲染外观（Flutter 默认 FontWeight.normal=400）一致。
  static const int defaultFontWeight = 400;

  /// 辉光触发阈值系数最小值
  ///
  /// 触发阈值 = 歌词字长中位数 × 该系数；系数越小越容易触发辉光。
  static const double minGlowThresholdFactor = 1.0;

  /// 辉光触发阈值系数最大值
  static const double maxGlowThresholdFactor = 2.0;

  /// 辉光触发阈值系数默认值
  static const double defaultGlowThresholdFactor = 1.2;

  /// 辉光固定时长判定阈值下限（ms）。
  static const double minGlowFixedThresholdMs = 500;

  /// 辉光固定时长判定阈值上限（ms）。
  static const double maxGlowFixedThresholdMs = 2000;

  /// 辉光固定时长判定阈值默认值（ms）。
  static const double defaultGlowFixedThresholdMs = 1000;

  // ============== 歌词辉光强度 ==============

  /// 辉光强度倍数下限。
  ///
  /// 0.2 时辉光只剩一层极淡的光晕，接近"关闭辉光观感"但保留开关状态，
  /// 不会出现"开关开着却完全没效果"的死档。
  static const double minGlowIntensity = 0.2;

  /// 辉光强度倍数上限。
  ///
  /// 2.0 时紧贴笔画的环带 alpha 从约 0.25 提到约 0.45（实测），再高会
  /// 让白色歌词的笔画边缘过曝、与背景对比度反转。
  static const double maxGlowIntensity = 2.0;

  /// 辉光强度倍数默认值。
  ///
  /// 1.0 = 历史行为（辉光剖面按 `EmphasizeEffect.glowLevel` 原样输出），
  /// 确保升级后视觉不变。
  static const double defaultGlowIntensity = 1.0;

  // ============== 辉光字符缩放开关 ==============

  /// 辉光字符缩放开关默认值。
  ///
  /// true = 历史行为：强调字凸起时放大（最高 1.12×）并左右外扩。
  /// false = 只停掉放大与水平外扩，仍保留上浮、正弦浮层与辉光呼吸——
  /// 让不喜欢"字被顶大"的用户能保留发光但不要弹跳。
  static const bool defaultGlowCharScale = true;

  /// 非当前行缩放最小值。
  ///
  /// 0.80 时背景行明显后退，再小会与当前行脱节。
  static const double minInactiveScale = 0.80;

  /// 非当前行缩放最大值。1.0 = 关闭缩放（所有行等大）。
  static const double maxInactiveScale = 1.00;

  /// 非当前行缩放默认值。
  ///
  /// 0.850：默认让背景行比当前行略小，突出当前行。仅对新安装用户生效，
  /// 已持久化的旧值不会被覆盖。
  static const double defaultInactiveScale = 0.850;

  /// 非当前行缩放滑块档位：0.80~1.00 共 40 档，步长 0.005。
  static const int inactiveScaleDivisions = 40;

  /// 当前行垂直锚位最小值（视口高度比例）。
  ///
  /// 0.15 时当前行贴近顶部，上方几乎不显示已唱过的行。
  static const double minAlignPosition = 0.15;

  /// 当前行垂直锚位最大值。
  ///
  /// 0.65 时当前行偏下，下方待唱行明显多于上方。
  static const double maxAlignPosition = 0.65;

  /// 当前行垂直锚位默认值。
  ///
  /// 保持历史写死值 0.35（AMLL 默认偏中上），确保升级后视觉不变。
  static const double defaultAlignPosition = 0.35;

  /// 锚位滑块档位：0.15~0.65 共 50 档，步长 0.01。
  static const int alignPositionDivisions = 50;

  /// 级联错峰最大延迟下限（ms）。
  static const double minCascadeMaxDelayMs = 100;

  /// 级联错峰最大延迟上限（ms）。
  static const double maxCascadeMaxDelayMs = 2000;

  /// 级联错峰最大延迟默认（ms）：越靠下的行最大"粘"这么久才回位。
  static const double defaultCascadeMaxDelayMs = 750;

  /// 级联错峰步长下限（ms）。
  static const double minCascadeBaseStepMs = 20;

  /// 级联错峰步长上限（ms）。
  static const double maxCascadeBaseStepMs = 200;

  /// 级联错峰步长默认（ms）：相邻行的错峰时间间隔。
  static const double defaultCascadeBaseStepMs = 60;

  /// 级联衰减分母下限（x in 1/x）。
  static const double minCascadeDecayX = 1.0;

  /// 级联衰减分母上限（x in 1/x）。
  static const double maxCascadeDecayX = 2.0;

  /// 级联衰减分母默认（x in 1/x）：每越过一行步长 × 1/x。
  static const double defaultCascadeDecayX = 1.1;

  /// 已播字上浮高度最小值（px）。0 = 完全不上浮。
  static const double minLiftHeightPx = 0.0;

  /// 已播字上浮高度最大值（px）。
  ///
  /// 10px 已明显超过一行字高的十分之一量级，再大会让当前行"飘"离基线。
  static const double maxLiftHeightPx = 10.0;

  /// 已播字上浮高度默认值（px）。
  ///
  /// 保持历史写死值 3.0（AMLL：当前字最大上浮 -3px），确保升级后视觉不变。
  /// 渲染侧取负值作为 Y 偏移（向上为负）。
  static const double defaultLiftHeightPx = 3.0;

  /// 级联错峰是否从当前行开始（默认 true）。
  ///
  /// - true：仅当前行及以下的行错峰跟随，当前行 delay=0，上方行不参与
  ///   「按住等错峰」，随全局滚动同步回位；
  /// - false：历史行为，从视口顶部行开始逐行累加错峰（上方行也错峰）。
  static const bool defaultStaggerFromCurrentLine = true;

  // ============== 歌词模糊强度 ==============

  /// 歌词模糊强度倍数下限。
  ///
  /// 0.5 时非当前行几乎清晰，是"关闭模糊观感"与"保留距离分级"的折中下限。
  static const double minBlurIntensity = 0.5;

  /// 歌词模糊强度倍数上限。
  ///
  /// 2.0 时最远行 sigma 达 10（原上限 5），再大会让整屏文字不可辨认，
  /// 且离屏渲染的模糊图尺寸（padding=σ×3）显著膨胀。
  static const double maxBlurIntensity = 2.0;

  /// 歌词模糊强度倍数默认值。
  ///
  /// 1.0 = 历史行为（sigma 等于距离分级值 1~5），确保升级后视觉不变。
  static const double defaultBlurIntensity = 1.0;

  // ============== 按设备类型的默认值（手机 / Pad） ==============

  /// 按设备类型的字号默认：手机 29px，Pad 40px。
  static double get _deviceDefaultFontSize => _isPadDevice() ? 40 : 29;

  /// 按设备类型的字重默认：手机半粗(w600)，Pad 黑体(w900)。
  static int get _deviceDefaultFontWeight => _isPadDevice() ? 900 : 600;

  /// 按设备类型的行间距默认：手机 1.4x，Pad 0.9x。
  static double get _deviceDefaultLineSpacing => _isPadDevice() ? 0.9 : 1.4;

  /// 是否 Pad 设备（物理屏幕最短边 >= 600dp），与 DeviceProvider 判断一致。
  /// 用于首次使用 / 重置时按设备类型提供差异化歌词默认值。
  static bool _isPadDevice() {
    final view = ui.PlatformDispatcher.instance.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.shortestSide >= 600;
  }

  // ============== 持久化 keys ==============

  static const String _keyFontSize = 'lyric_font_size';
  static const String _keyLineSpacing = 'lyric_line_spacing';
  static const String _keyFontWeight = 'lyric_font_weight';
  static const String _keyUseGaussianBlur = 'lyric_use_gaussian_blur';
  static const String _keyBlurIntensity = 'lyric_blur_intensity';
  static const String _keyUseGlowEffect = 'lyric_use_glow_effect';
  static const String _keyUseFlowingBackground = 'lyric_use_flowing_background';
  static const String _keyFontSource = 'lyric_font_source';
  static const String _keyCustomFontPath = 'lyric_custom_font_path';
  static const String _keyShowTranslation = 'lyric_show_translation';
  static const String _keyDisplayMode = 'lyric_display_mode';
  static const String _keyUseDuetLayout = 'lyric_use_duet_layout';
  static const String _keyLineBalance = 'lyric_line_balance';
  static const String _keyEcoMode = 'lyric_eco_mode';
  static const String _keyUseDynamicLyricColor = 'lyric_dynamic_color';
  static const String _keyGlowThresholdFactor = 'lyric_glow_threshold_factor';
  static const String _keyGlowThresholdMode = 'lyric_glow_threshold_mode';
  static const String _keyGlowFixedThresholdMs =
      'lyric_glow_fixed_threshold_ms';
  static const String _keyGlowIntensity = 'lyric_glow_intensity';
  static const String _keyGlowCharScale = 'lyric_glow_char_scale';
  static const String _keyFillMode = 'lyric_fill_mode';
  static const String _keyInactiveScale = 'lyric_inactive_scale';
  static const String _keyAlignPosition = 'lyric_align_position';
  static const String _keyCascadeMaxDelayMs = 'lyric_cascade_max_delay_ms';
  static const String _keyCascadeBaseStepMs = 'lyric_cascade_base_step_ms';
  static const String _keyCascadeDecayX = 'lyric_cascade_decay_x';
  static const String _keyLiftHeightPx = 'lyric_lift_height_px';
  static const String _keyStaggerFromCurrentLine =
      'lyric_stagger_from_current';

  // ============== 当前值 ==============

  double _fontSize = defaultUserFontSize;
  double _lineSpacing = defaultLineSpacing;
  int _fontWeight = defaultFontWeight;
  bool _useGaussianBlur = false;
  // 歌词模糊强度倍数（默认 1.0 = 历史行为）
  double _blurIntensity = defaultBlurIntensity;
  bool _useGlowEffect = true;
  // 辉光强度倍数（默认 1.0 = 历史行为）
  double _glowIntensity = defaultGlowIntensity;
  // 辉光字符缩放（默认开启）：关闭后只停放大与外扩，保留上浮/浮层/辉光亮度
  bool _glowCharScale = defaultGlowCharScale;
  bool _useFlowingBackground = false;
  bool _useDuetLayout = false;
  // 平衡行换行（默认开启）：长歌词行用 DP 求均衡断点，见 LyricWrapPlanner
  bool _lineBalance = true;
  bool _showTranslation = true;
  LyricDisplayMode _displayMode = LyricDisplayMode.translation;
  LyricFontSource _fontSource = LyricFontSource.system;
  String? _customFontPath;
  // 歌词省电模式（默认开启）：开启后歌词界面锁定 60fps，用户上下滑动歌词时临时解锁
  bool _ecoMode = true;
  // 动态字体颜色（默认开启，仅 AM 播放器可用）：当前行歌词颜色按「70% 白 + 30% 封面提取色」混色
  bool _useDynamicLyricColor = true;
  // 辉光触发阈值系数（默认 1.2）：触发阈值 = 歌词字长中位数 × 该系数
  double _glowThresholdFactor = defaultGlowThresholdFactor;
  // 辉光判定模式（默认固定时长）：不再随 BPM/字长自适应推断
  GlowThresholdMode _glowThresholdMode = GlowThresholdMode.fixed;
  // 辉光固定时长判定阈值（ms，默认 1000）
  double _glowFixedThresholdMs = defaultGlowFixedThresholdMs;
  // 字内渐变模型：默认 sweep（扫光），classic 为原有观感
  LyricFillMode _fillMode = LyricFillMode.sweep;
  // 非当前行缩放（默认 0.850）：清晰层非当前行与 AM 模糊层共用此值
  double _inactiveScale = defaultInactiveScale;
  // 当前行垂直锚位（默认 0.35）：当前行中心落在视口高度的该比例处
  double _alignPosition = defaultAlignPosition;
  // 级联错峰三参数（默认 = 当前调好的手感值）
  double _cascadeMaxDelayMs = defaultCascadeMaxDelayMs;
  double _cascadeBaseStepMs = defaultCascadeBaseStepMs;
  double _cascadeDecayX = defaultCascadeDecayX;
  // AM 歌词细节参数：已播字上浮高度（px）
  double _liftHeightPx = defaultLiftHeightPx;
  // 级联错峰起点：true = 从当前行开始（默认），false = 从视口顶部开始（历史行为）
  bool _staggerFromCurrentLine = defaultStaggerFromCurrentLine;
  // 运行时加载成功后填充的 family（仅 custom 模式且加载成功时非 null）
  String? _loadedCustomFontFamily;
  bool _loaded = false;

  double get fontSize => _fontSize;
  double get lineSpacing => _lineSpacing;

  /// 歌词字重（FontWeight.value 数值，范围 [minFontWeight]~[maxFontWeight]）。
  int get fontWeightValue => _fontWeight;

  /// 歌词字重对应 [FontWeight]（供 TextStyle 使用）。
  FontWeight get fontWeight => FontWeight(_fontWeight);
  bool get useGaussianBlur => _useGaussianBlur;

  /// 歌词模糊强度倍数（范围 [minBlurIntensity]~[maxBlurIntensity]）。
  ///
  /// 非当前行模糊图的 sigma = 距离分级值 × 本倍数，见
  /// AppleLyricsView._blurGeometry。倍数保持"离当前行越远越糊"的相对关系。
  double get blurIntensity => _blurIntensity;

  bool get useGlowEffect => _useGlowEffect;

  /// 歌词辉光强度倍数（范围 [minGlowIntensity]~[maxGlowIntensity]）。
  ///
  /// 辉光层每帧的 alpha = `EmphasizeState.glowLevel × 本倍数`（clamp 到 1.0），
  /// 超出 1.0 的部分改用 `BlendMode.plus` 追加一层——只提亮度，不改光形。
  double get glowIntensity => _glowIntensity;

  /// 辉光字符缩放是否开启（默认开启）。
  ///
  /// 关闭后强调字不再被放大（`scale` 恒 1.0）与左右外扩（`offsetXEm` 恒 0），
  /// 上浮（`offsetYEm`）、正弦浮层（`floatYEm`）与辉光亮度（`glowLevel`）不受影响。
  bool get useGlowCharScale => _glowCharScale;
  bool get useFlowingBackground => _useFlowingBackground;
  bool get useDuetLayout => _useDuetLayout;

  /// 平衡行换行是否开启（默认开启）。
  ///
  /// 开启后长歌词行的断点由 `LyricWrapPlanner` 用 DP 求「各行宽度最均匀」的方案；
  /// 关闭则退回旧的「累加宽度超可用宽即换行」贪心（行为与改造前逐字一致）。
  bool get lineBalance => _lineBalance;
  bool get showTranslation => _showTranslation;
  LyricDisplayMode get displayMode => _displayMode;
  LyricFontSource get fontSource => _fontSource;
  String? get customFontPath => _customFontPath;

  /// 歌词省电模式是否开启（默认开启）。
  bool get ecoMode => _ecoMode;

  /// 歌词动态字体颜色是否开启（默认开启，仅 AM 播放器生效）。
  bool get useDynamicLyricColor => _useDynamicLyricColor;

  /// 辉光触发阈值系数（范围 [minGlowThresholdFactor]~[maxGlowThresholdFactor]）。
  ///
  /// 触发阈值 = 歌词字长中位数 × 该系数；系数越小越容易触发辉光。
  double get glowThresholdFactor => _glowThresholdFactor;

  /// 辉光触发判定模式（默认 [GlowThresholdMode.fixed]）。
  ///
  /// [GlowThresholdMode.adaptive] = 原有判定（BPM/字长中位数 × 系数），
  /// [GlowThresholdMode.fixed] = 固定时长判定（[glowFixedThresholdMs]）。
  GlowThresholdMode get glowThresholdMode => _glowThresholdMode;

  /// 辉光固定时长判定阈值（ms，范围 [minGlowFixedThresholdMs]~
  /// [maxGlowFixedThresholdMs]）。仅 [glowThresholdMode] 为 fixed 时生效。
  double get glowFixedThresholdMs => _glowFixedThresholdMs;

  /// 字内渐变（当前行扫光）模型，默认 [LyricFillMode.sweep]。
  ///
  /// 仅影响当前行的字内渐变；非当前行的 alpha 路径与关闭渐变时不受影响。
  LyricFillMode get fillMode => _fillMode;

  /// 非当前行缩放（范围 [minInactiveScale]~[maxInactiveScale]）。
  ///
  /// 清晰层非当前行的 canvas.scale 与 AM 歌词模糊层离屏渲染缩放共用此值，
  /// 因此调节后两层始终严格重合，改变的只是背景行相对当前行的后退程度。
  double get inactiveScale => _inactiveScale;

  /// 当前行垂直锚位（范围 [minAlignPosition]~[maxAlignPosition]）。
  ///
  /// 滚动目标公式 `targetY = -(lineTop + lineHeight/2 - viewportHeight × 本值)`，
  /// 即当前行中心停在视口高度的该比例处。
  double get alignPosition => _alignPosition;

  /// 级联错峰最大延迟（ms）。范围 [minCascadeMaxDelayMs]~[maxCascadeMaxDelayMs]。
  double get cascadeMaxDelayMs => _cascadeMaxDelayMs;

  /// 级联错峰步长（ms）。范围 [minCascadeBaseStepMs]~[maxCascadeBaseStepMs]。
  double get cascadeBaseStepMs => _cascadeBaseStepMs;

  /// 级联衰减分母（x in 1/x）。范围 [minCascadeDecayX]~[maxCascadeDecayX]。
  double get cascadeDecayX => _cascadeDecayX;

  /// 级联衰减因子（已折算 1/x）。供推进循环直接用。
  double get cascadeStepDecay => 1.0 / _cascadeDecayX;

  /// 已播字上浮高度（px，范围 [minLiftHeightPx]~[maxLiftHeightPx]）。
  ///
  /// 当前行中"已唱过"的字（word 索引小于当前演唱字）稳定停留在这个上浮量上，
  /// 未唱字保持 0；渲染侧使用的 Y 偏移为其负值。
  double get liftHeightPx => _liftHeightPx;

  /// 级联错峰是否从当前行开始（默认 true）。
  bool get staggerFromCurrentLine => _staggerFromCurrentLine;

  /// 当前生效的 fontFamily（传给 TextPainter 的 TextStyle）：
  /// - [LyricFontSource.system]：返回 null（让 Flutter 走系统字体链）
  /// - [LyricFontSource.bundled]：已废弃（内置 SimHei 已移除），等同 system 返回 null
  /// - [LyricFontSource.custom]：返回 [_loadedCustomFontFamily]，
  ///   加载失败时为 null（实际降级为 system 行为）
  String? get effectiveFontFamily {
    switch (_fontSource) {
      case LyricFontSource.system:
      case LyricFontSource.bundled:
        return null;
      case LyricFontSource.custom:
        return _loadedCustomFontFamily;
    }
  }

  /// 计算实际行高系数。
  ///
  /// 公式：`actualLineHeight = (fontSize / defaultFontSize) * lineSpacing`
  /// 例如：
  /// - fontSize=15, lineSpacing=1.5 → (15/15)*1.5 = 1.5
  /// - fontSize=15, lineSpacing=1.0 → (15/15)*1.0 = 1.0
  /// - fontSize=20, lineSpacing=1.0 → (20/15)*1.0 ≈ 1.33
  double get lineHeightMultiplier =>
      (_fontSize / defaultFontSize) * _lineSpacing;

  /// 仅供测试：重置加载标记，使下一次 [load] 重新从 [backend] 读取。
  ///
  /// [load] 带 `_loaded` 幂等守卫，单例跨用例复用时后续调用直接返回，
  /// 测试需在 setUp 中先调用本方法再注入新的 backend。
  @visibleForTesting
  static void resetForTest() {
    instance._loaded = false;
  }

  /// 从 [backend] 加载。App 启动时调用一次。
  Future<void> load() async {
    if (_loaded) return;
    // 首次使用（key 不存在）时按设备类型提供差异化默认：
    // 手机 29px/半粗(600)/1.4x；Pad 40px/黑体(900)/0.9x。
    // 用户后续手动调整后会持久化，届时尊重用户设置。
    _fontSize = backend.getDouble(_keyFontSize) ?? _deviceDefaultFontSize;
    _lineSpacing = backend.getDouble(_keyLineSpacing) ?? _deviceDefaultLineSpacing;
    _fontWeight =
        (backend.getInt(_keyFontWeight) ?? _deviceDefaultFontWeight)
            .clamp(minFontWeight, maxFontWeight);
    _useGaussianBlur = backend.getBool(_keyUseGaussianBlur) ?? false;
    _blurIntensity =
        (backend.getDouble(_keyBlurIntensity) ?? defaultBlurIntensity)
            .clamp(minBlurIntensity, maxBlurIntensity);
    _useGlowEffect = backend.getBool(_keyUseGlowEffect) ?? true;
    _glowIntensity =
        (backend.getDouble(_keyGlowIntensity) ?? defaultGlowIntensity)
            .clamp(minGlowIntensity, maxGlowIntensity);
    _glowCharScale =
        backend.getBool(_keyGlowCharScale) ?? defaultGlowCharScale;
    _useFlowingBackground = backend.getBool(_keyUseFlowingBackground) ?? false;
    _useDuetLayout = backend.getBool(_keyUseDuetLayout) ?? false;
    _lineBalance = backend.getBool(_keyLineBalance) ?? true;
    _showTranslation = backend.getBool(_keyShowTranslation) ?? true;
    _displayMode = _displayModeFromName(backend.getString(_keyDisplayMode));
    _fontSource = _fontSourceFromName(backend.getString(_keyFontSource));
    _customFontPath = backend.getString(_keyCustomFontPath);
    _ecoMode = backend.getBool(_keyEcoMode) ?? true;
    _useDynamicLyricColor = backend.getBool(_keyUseDynamicLyricColor) ?? true;
    _glowThresholdFactor =
        (backend.getDouble(_keyGlowThresholdFactor) ?? defaultGlowThresholdFactor)
            .clamp(minGlowThresholdFactor, maxGlowThresholdFactor);
    _glowThresholdMode = _glowThresholdModeFromName(
      backend.getString(_keyGlowThresholdMode),
    );
    _glowFixedThresholdMs =
        (backend.getDouble(_keyGlowFixedThresholdMs) ??
                defaultGlowFixedThresholdMs)
            .clamp(minGlowFixedThresholdMs, maxGlowFixedThresholdMs);
    _fillMode = _fillModeFromName(backend.getString(_keyFillMode));
    _inactiveScale = (backend.getDouble(_keyInactiveScale) ?? defaultInactiveScale)
        .clamp(minInactiveScale, maxInactiveScale);
    _alignPosition =
        (backend.getDouble(_keyAlignPosition) ?? defaultAlignPosition)
            .clamp(minAlignPosition, maxAlignPosition);
    _cascadeMaxDelayMs =
        (backend.getDouble(_keyCascadeMaxDelayMs) ?? defaultCascadeMaxDelayMs)
            .clamp(minCascadeMaxDelayMs, maxCascadeMaxDelayMs);
    _cascadeBaseStepMs =
        (backend.getDouble(_keyCascadeBaseStepMs) ?? defaultCascadeBaseStepMs)
            .clamp(minCascadeBaseStepMs, maxCascadeBaseStepMs);
    _cascadeDecayX =
        (backend.getDouble(_keyCascadeDecayX) ?? defaultCascadeDecayX)
            .clamp(minCascadeDecayX, maxCascadeDecayX);
    _liftHeightPx =
        (backend.getDouble(_keyLiftHeightPx) ?? defaultLiftHeightPx)
            .clamp(minLiftHeightPx, maxLiftHeightPx);
    _staggerFromCurrentLine =
        backend.getBool(_keyStaggerFromCurrentLine) ??
            defaultStaggerFromCurrentLine;
    _loaded = true;
    notifyListeners();
    // 若已配置自定义字体，立即尝试加载（Fire-and-forget，加载完成后会 notifyListeners）
    if (_fontSource == LyricFontSource.custom) {
      await _tryLoadCustomFont();
    }
  }

  /// 设置字号并持久化。会触发 [notifyListeners]。
  Future<void> setFontSize(double size) async {
    final clamped = size.clamp(minFontSize, maxFontSize);
    if (clamped == _fontSize) return;
    _fontSize = clamped;
    notifyListeners();
    await backend.setDouble(_keyFontSize, _fontSize);
  }

  /// 设置行间距系数并持久化。
  Future<void> setLineSpacing(double spacing) async {
    final clamped = spacing.clamp(minLineSpacing, maxLineSpacing);
    if (clamped == _lineSpacing) return;
    _lineSpacing = clamped;
    notifyListeners();
    await backend.setDouble(_keyLineSpacing, _lineSpacing);
  }

  /// 设置字重并持久化。会触发 [notifyListeners]。
  Future<void> setFontWeight(int value) async {
    final clamped = value.clamp(minFontWeight, maxFontWeight);
    if (clamped == _fontWeight) return;
    _fontWeight = clamped;
    notifyListeners();
    await backend.setInt(_keyFontWeight, _fontWeight);
  }

  /// 设置高斯模糊开关并持久化。
  Future<void> setUseGaussianBlur(bool enabled) async {
    if (_useGaussianBlur == enabled) return;
    _useGaussianBlur = enabled;
    notifyListeners();
    await backend.setBool(_keyUseGaussianBlur, enabled);
  }

  /// 设置歌词模糊强度倍数并持久化。
  Future<void> setBlurIntensity(double value) async {
    final clamped = value.clamp(minBlurIntensity, maxBlurIntensity);
    if (clamped == _blurIntensity) return;
    _blurIntensity = clamped;
    notifyListeners();
    await backend.setDouble(_keyBlurIntensity, _blurIntensity);
  }

  /// 设置辉光效果开关并持久化。
  Future<void> setUseGlowEffect(bool enabled) async {
    if (_useGlowEffect == enabled) return;
    _useGlowEffect = enabled;
    notifyListeners();
    await backend.setBool(_keyUseGlowEffect, enabled);
  }

  /// 设置动态流光背景开关并持久化。
  Future<void> setUseFlowingBackground(bool enabled) async {
    if (_useFlowingBackground == enabled) return;
    _useFlowingBackground = enabled;
    notifyListeners();
    await backend.setBool(_keyUseFlowingBackground, enabled);
  }

  /// 设置男女对唱歌词优化开关并持久化。
  Future<void> setUseDuetLayout(bool enabled) async {
    if (_useDuetLayout == enabled) return;
    _useDuetLayout = enabled;
    notifyListeners();
    await backend.setBool(_keyUseDuetLayout, enabled);
  }

  /// 设置平衡行换行开关并持久化。
  Future<void> setLineBalance(bool enabled) async {
    if (_lineBalance == enabled) return;
    _lineBalance = enabled;
    notifyListeners();
    await backend.setBool(_keyLineBalance, enabled);
  }

  /// 设置歌词省电模式开关并持久化。
  /// 开启后歌词界面锁定 60fps，用户上下滑动歌词时临时解锁帧率限制。
  Future<void> setEcoMode(bool enabled) async {
    if (_ecoMode == enabled) return;
    _ecoMode = enabled;
    notifyListeners();
    await backend.setBool(_keyEcoMode, enabled);
  }

  /// 设置歌词动态字体颜色开关并持久化。
  /// 开启后当前行歌词颜色按「70% 白 + 30% 封面提取色」混色（仅 AM 播放器生效）。
  Future<void> setUseDynamicLyricColor(bool enabled) async {
    if (_useDynamicLyricColor == enabled) return;
    _useDynamicLyricColor = enabled;
    notifyListeners();
    await backend.setBool(_keyUseDynamicLyricColor, enabled);
  }

  /// 设置辉光触发阈值系数并持久化。
  ///
  /// 触发阈值 = 歌词字长中位数 × 该系数，范围 [minGlowThresholdFactor]~
  /// [maxGlowThresholdFactor]（默认 [defaultGlowThresholdFactor]=1.2）。
  /// 系数越小越容易触发辉光。
  Future<void> setGlowThresholdFactor(double value) async {
    final clamped =
        value.clamp(minGlowThresholdFactor, maxGlowThresholdFactor);
    if (clamped == _glowThresholdFactor) return;
    _glowThresholdFactor = clamped;
    notifyListeners();
    await backend.setDouble(_keyGlowThresholdFactor, _glowThresholdFactor);
  }

  /// 设置辉光强度倍数并持久化。
  ///
  /// 范围 [minGlowIntensity]~[maxGlowIntensity]（默认 [defaultGlowIntensity]=1.0）。
  /// 只调亮度、不改光形：超过 1.0 的部分以加法叠加，剖面半径不变。
  Future<void> setGlowIntensity(double value) async {
    final clamped = value.clamp(minGlowIntensity, maxGlowIntensity);
    if (clamped == _glowIntensity) return;
    _glowIntensity = clamped;
    notifyListeners();
    await backend.setDouble(_keyGlowIntensity, _glowIntensity);
  }

  /// 设置辉光字符缩放开关并持久化。
  ///
  /// 关闭只停掉强调字的放大与水平外扩，上浮 / 正弦浮层 / 辉光亮度照常。
  Future<void> setUseGlowCharScale(bool enabled) async {
    if (_glowCharScale == enabled) return;
    _glowCharScale = enabled;
    notifyListeners();
    await backend.setBool(_keyGlowCharScale, enabled);
  }

  /// 设置辉光触发判定模式并持久化。
  Future<void> setGlowThresholdMode(GlowThresholdMode mode) async {
    if (_glowThresholdMode == mode) return;
    _glowThresholdMode = mode;
    notifyListeners();
    await backend.setString(_keyGlowThresholdMode, mode.name);
  }

  /// 设置辉光固定时长判定阈值并持久化。
  ///
  /// 范围 [minGlowFixedThresholdMs]~[maxGlowFixedThresholdMs]
  /// （默认 [defaultGlowFixedThresholdMs]=1000）。仅 fixed 判定模式生效。
  Future<void> setGlowFixedThresholdMs(double value) async {
    final clamped =
        value.clamp(minGlowFixedThresholdMs, maxGlowFixedThresholdMs);
    if (clamped == _glowFixedThresholdMs) return;
    _glowFixedThresholdMs = clamped;
    notifyListeners();
    await backend.setDouble(_keyGlowFixedThresholdMs, _glowFixedThresholdMs);
  }

  /// 设置字内渐变（扫光）模型并持久化。
  Future<void> setFillMode(LyricFillMode mode) async {
    if (_fillMode == mode) return;
    _fillMode = mode;
    notifyListeners();
    await backend.setString(_keyFillMode, mode.name);
  }

  /// 设置非当前行缩放并持久化。
  ///
  /// 该值同时驱动清晰层非当前行的 canvas.scale 与 AM 歌词模糊层离屏渲染缩放，
  /// 因此调节后两层始终严格重合，改变的只是背景行相对当前行的后退程度。
  Future<void> setInactiveScale(double value) async {
    final clamped = value.clamp(minInactiveScale, maxInactiveScale);
    if (clamped == _inactiveScale) return;
    _inactiveScale = clamped;
    notifyListeners();
    await backend.setDouble(_keyInactiveScale, _inactiveScale);
  }

  /// 设置当前行垂直锚位并持久化。
  ///
  /// 锚位变化由 posY 弹簧在下一次 `setCurrentLine` 时重新求 target 自然生效，
  /// 无需额外失效任何布局缓存（行高/行顶与锚位无关）。
  Future<void> setAlignPosition(double value) async {
    final clamped = value.clamp(minAlignPosition, maxAlignPosition);
    if (clamped == _alignPosition) return;
    _alignPosition = clamped;
    notifyListeners();
    await backend.setDouble(_keyAlignPosition, _alignPosition);
  }

  /// 设置级联错峰最大延迟并持久化。
  Future<void> setCascadeMaxDelayMs(double value) async {
    final clamped = value.clamp(minCascadeMaxDelayMs, maxCascadeMaxDelayMs);
    if (clamped == _cascadeMaxDelayMs) return;
    _cascadeMaxDelayMs = clamped;
    notifyListeners();
    await backend.setDouble(_keyCascadeMaxDelayMs, _cascadeMaxDelayMs);
  }

  /// 设置级联错峰步长并持久化。
  Future<void> setCascadeBaseStepMs(double value) async {
    final clamped = value.clamp(minCascadeBaseStepMs, maxCascadeBaseStepMs);
    if (clamped == _cascadeBaseStepMs) return;
    _cascadeBaseStepMs = clamped;
    notifyListeners();
    await backend.setDouble(_keyCascadeBaseStepMs, _cascadeBaseStepMs);
  }

  /// 设置级联衰减分母（x in 1/x）并持久化。
  Future<void> setCascadeDecayX(double value) async {
    final clamped = value.clamp(minCascadeDecayX, maxCascadeDecayX);
    if (clamped == _cascadeDecayX) return;
    _cascadeDecayX = clamped;
    notifyListeners();
    await backend.setDouble(_keyCascadeDecayX, _cascadeDecayX);
  }

  /// 设置已播字上浮高度（px）并持久化。
  Future<void> setLiftHeightPx(double value) async {
    final clamped = value.clamp(minLiftHeightPx, maxLiftHeightPx);
    if (clamped == _liftHeightPx) return;
    _liftHeightPx = clamped;
    notifyListeners();
    await backend.setDouble(_keyLiftHeightPx, _liftHeightPx);
  }

  /// 设置级联错峰起点（从当前行开始）并持久化。
  Future<void> setStaggerFromCurrentLine(bool enabled) async {
    if (_staggerFromCurrentLine == enabled) return;
    _staggerFromCurrentLine = enabled;
    notifyListeners();
    await backend.setBool(_keyStaggerFromCurrentLine, enabled);
  }

  /// 设置歌词翻译副行显示开关并持久化。
  Future<void> setShowTranslation(bool enabled) async {
    if (_showTranslation == enabled) return;
    _showTranslation = enabled;
    notifyListeners();
    await backend.setBool(_keyShowTranslation, enabled);
  }

  /// 设置辅助行显示模式（翻译/罗马音）并持久化。
  Future<void> setDisplayMode(LyricDisplayMode mode) async {
    if (_displayMode == mode) return;
    _displayMode = mode;
    notifyListeners();
    await backend.setString(_keyDisplayMode, mode.name);
  }

  // ============== 歌词字体来源 ==============

  /// 设置字体来源并持久化。
  Future<void> setFontSource(LyricFontSource source) async {
    if (_fontSource == source) return;
    _fontSource = source;
    notifyListeners();
    await backend.setString(_keyFontSource, source.name);
  }

  /// 设置自定义字体文件路径并立即尝试加载注册。
  /// 传 null 清除路径并卸载已加载的字体（实际效果降级到 system）。
  Future<void> setCustomFontPath(String? path) async {
    if (_customFontPath == path) return;
    _customFontPath = path;
    if (path != null) {
      await backend.setString(_keyCustomFontPath, path);
      await _tryLoadCustomFont();
    } else {
      await backend.remove(_keyCustomFontPath);
      _loadedCustomFontFamily = null;
      notifyListeners();
    }
  }

  /// 内部：尝试用 FontLoader 加载 [_customFontPath] 指向的字体文件。
  /// 加载成功则填充 [_loadedCustomFontFamily] 并 notifyListeners。
  ///
  /// 注意：Flutter 的 FontLoader 不支持对同一 family name 重复调用 load()，
  /// 否则会抛异常。因此每次加载使用带计数器的唯一 family name。
  int _fontLoadCounter = 0;
  Future<void> _tryLoadCustomFont() async {
    final path = _customFontPath;
    if (path == null || path.isEmpty) {
      _loadedCustomFontFamily = null;
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      // ignore: avoid_print
      print('[LyricPreferences] 字体文件不存在: $path');
      _loadedCustomFontFamily = null;
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      // 每次使用唯一的 family name，避免 FontLoader 重复注册同一 family 抛异常
      _fontLoadCounter++;
      final familyName = '$lyricCustomFontFamily#$_fontLoadCounter';
      final loader = FontLoader(familyName);
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loadedCustomFontFamily = familyName;
      notifyListeners();
    } catch (e) {
      // ignore: avoid_print
      print('[LyricPreferences] 字体加载失败: $e');
      _loadedCustomFontFamily = null;
      notifyListeners();
    }
  }

  /// 历史值 'bundled'（内置 SimHei 已移除）迁移为 [LyricFontSource.system]。
  static LyricFontSource _fontSourceFromName(String? name) {
    switch (name) {
      case 'custom':
        return LyricFontSource.custom;
      default:
        // 'bundled' 与未知值一并归入 system（bundled 字体已不再打包）
        return LyricFontSource.system;
    }
  }

  static LyricDisplayMode _displayModeFromName(String? name) {
    return name == 'roma' ? LyricDisplayMode.roma : LyricDisplayMode.translation;
  }

  static LyricFillMode _fillModeFromName(String? name) {
    return name == 'classic' ? LyricFillMode.classic : LyricFillMode.sweep;
  }

  static GlowThresholdMode _glowThresholdModeFromName(String? name) {
    return name == 'adaptive'
        ? GlowThresholdMode.adaptive
        : GlowThresholdMode.fixed;
  }

  /// 重置为默认值（按设备类型：手机 / Pad 差异化默认）。
  Future<void> reset() async {
    _fontSize = _deviceDefaultFontSize;
    _lineSpacing = _deviceDefaultLineSpacing;
    _fontWeight = _deviceDefaultFontWeight;
    _useGaussianBlur = false;
    _blurIntensity = defaultBlurIntensity;
    _useGlowEffect = true;
    _glowIntensity = defaultGlowIntensity;
    _glowCharScale = defaultGlowCharScale;
    _useFlowingBackground = false;
    _useDuetLayout = false;
    _lineBalance = true;
    _showTranslation = true;
    _displayMode = LyricDisplayMode.translation;
    _fontSource = LyricFontSource.system;
    _customFontPath = null;
    _loadedCustomFontFamily = null;
    _ecoMode = true;
    _useDynamicLyricColor = true;
    _glowThresholdFactor = defaultGlowThresholdFactor;
    _glowThresholdMode = GlowThresholdMode.fixed;
    _glowFixedThresholdMs = defaultGlowFixedThresholdMs;
    _fillMode = LyricFillMode.sweep;
    _inactiveScale = defaultInactiveScale;
    _alignPosition = defaultAlignPosition;
    _cascadeMaxDelayMs = defaultCascadeMaxDelayMs;
    _cascadeBaseStepMs = defaultCascadeBaseStepMs;
    _cascadeDecayX = defaultCascadeDecayX;
    _liftHeightPx = defaultLiftHeightPx;
    _staggerFromCurrentLine = defaultStaggerFromCurrentLine;
    notifyListeners();
    await backend.setDouble(_keyFontSize, _fontSize);
    await backend.setDouble(_keyLineSpacing, _lineSpacing);
    await backend.setInt(_keyFontWeight, _fontWeight);
    await backend.setBool(_keyUseGaussianBlur, _useGaussianBlur);
    await backend.remove(_keyBlurIntensity);
    await backend.setBool(_keyUseGlowEffect, _useGlowEffect);
    await backend.setBool(_keyUseFlowingBackground, _useFlowingBackground);
    await backend.setBool(_keyUseDuetLayout, _useDuetLayout);
    await backend.setBool(_keyLineBalance, _lineBalance);
    await backend.setBool(_keyShowTranslation, _showTranslation);
    await backend.setString(_keyDisplayMode, _displayMode.name);
    await backend.remove(_keyEcoMode);
    await backend.remove(_keyUseDynamicLyricColor);
    await backend.remove(_keyGlowThresholdFactor);
    await backend.remove(_keyGlowThresholdMode);
    await backend.remove(_keyGlowFixedThresholdMs);
    await backend.remove(_keyGlowIntensity);
    await backend.remove(_keyGlowCharScale);
    await backend.remove(_keyFillMode);
    await backend.remove(_keyInactiveScale);
    await backend.remove(_keyAlignPosition);
    await backend.remove(_keyCascadeMaxDelayMs);
    await backend.remove(_keyCascadeBaseStepMs);
    await backend.remove(_keyCascadeDecayX);
    await backend.remove(_keyLiftHeightPx);
    await backend.remove(_keyStaggerFromCurrentLine);
    await backend.remove(_keyFontSource);
    await backend.remove(_keyCustomFontPath);
  }
}
