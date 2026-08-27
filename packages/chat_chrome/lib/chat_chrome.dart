/// Chat composer and keyboard-replacement emoji / sticker / GIF panel chrome.
///
/// Host integration: own a [KeyboardPanelController], mount [KeyboardPanel],
/// wire [EmojiDataSource], composer insert/delete, and aggregate chrome into
/// scroll `bottomPadding`. The controller is chrome SoT; the panel projects.
/// See the package README for ownership, silent paths, and data-source
/// contracts.
library;

export 'package:emoji_data/emoji_data.dart';

export 'src/composer/chat_enter_icons.dart';
export 'src/composer/chat_enter_top_view.dart';
export 'src/composer/chat_enter_view.dart';
export 'src/composer/chat_input_metrics.dart';
export 'src/composer/chat_content_bottom_fade.dart';
export 'src/glass/glass_backdrop_source.dart';
export 'src/glass/liquid_glass_shader.dart';
export 'src/glass/telegram_glass.dart';
export 'src/glass/telegram_glass_style.dart';
export 'src/debug/chat_chrome_log.dart';
export 'src/inset/chat_bottom_inset_controller.dart';
export 'src/inset/keyboard_panel_store.dart';
export 'src/motion/scale_pressable.dart';
export 'src/motion/keyboard_panel_motion.dart';
export 'src/panel/backspace_action_button.dart';
export 'src/panel/emoji_category_strip.dart';
export 'src/panel/emoji_color_picker.dart';
export 'src/panel/emoji_deferred_recents.dart';
export 'src/panel/emoji_glyph.dart';
export 'src/panel/emoji_glyph_cell.dart';
export 'src/panel/emoji_page.dart';
export 'src/panel/keyboard_panel.dart';
export 'src/panel/keyboard_panel_controller.dart';
export 'src/panel/keyboard_panel_allow.dart';
export 'src/panel/keyboard_panel_bottom_actions.dart';
export 'src/panel/keyboard_panel_bottom_bar.dart';
export 'src/panel/keyboard_panel_callbacks.dart';
export 'src/panel/keyboard_panel_labels.dart';
export 'src/panel/keyboard_panel_nav_bar_fade.dart';
export 'src/panel/emoji_search_field.dart';
export 'src/panel/emoji_tab_assets.dart';
export 'src/panel/keyboard_panel_type_tabs_pill.dart';
export 'src/panel/sticker_gif_stubs.dart';
export 'src/theme/chat_chrome_colors.dart';
