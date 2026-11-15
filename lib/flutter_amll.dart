/// flutter_amll —— Apple Music 风格（AMLL）逐字歌词渲染组件库。
///
/// 自 md3music 的 AM 风格播放页歌词 UI 完整抽取：保留全部渲染优化与可调节
/// 选项，且不依赖任何宿主业务代码。宿主只需注入少量平台能力即可接回自有实现（详见
/// [LyricPreferences.backend]、[AmllHaptics]、[AmllFontLoader]、[AmllToast]、
/// [AmllRemoteControl]）。
library;

export 'src/animation/spring.dart';
export 'src/apple_lyrics_view.dart';
export 'src/controllers/line_scale_controller.dart';
export 'src/controllers/lyric_scroll_controller.dart';
export 'src/layout/duet_layout.dart';
export 'src/layout/lyric_animation_preset_store.dart';
export 'src/layout/lyric_aux_scope.dart';
export 'src/layout/lyric_color_setting_tile.dart';
export 'src/layout/lyric_layout.dart';
export 'src/layout/lyric_preferences.dart';
export 'src/layout/lyric_preferences_panel.dart';
export 'src/models/aux_text_image.dart';
export 'src/models/lyric_line.dart';
export 'src/parsers/krc_parser.dart';
export 'src/parsers/lrc_parser.dart';
export 'src/parsers/lyric_parser_chain.dart';
export 'src/parsers/plaintext_parser.dart';
export 'src/parsers/ttml_parser.dart';
export 'src/platform/app_text_context_menu.dart';
export 'src/platform/build_flags.dart';
export 'src/platform/font_loader.dart';
export 'src/platform/frame_driver.dart';
export 'src/platform/haptics.dart';
export 'src/platform/remote_slider.dart';
export 'src/platform/toast.dart';
export 'src/preview/lyrics_preview_page.dart';
export 'src/storage/lyric_preferences_backend.dart';
export 'src/utils/hex_color.dart';
export 'src/utils/lyric_credit_filter.dart';
export 'src/utils/lyric_line_balance.dart';
export 'src/utils/lyric_line_color.dart';
export 'src/utils/lyric_position.dart';
export 'src/utils/lyric_wrap_plan.dart';
