/// Endless, anchor-based chat viewport.
///
/// Layout fans out from `(anchorMessageId, anchorPixelOffset)` rather than a
/// global content height. Integrate by implementing [ChatDataSource] and
/// embedding [ChatScrollView].
///
/// Host-facing helpers include [DatedMessage] (day separator + body),
/// [ChatMessageBody] (in-bubble content + meta last-line packing), and
/// [ChatBubbleMetrics] (theme + run → corner / padding resolvers).
library;

export 'src/chat_scroll/animate_to_load_policy.dart';
export 'src/chat_scroll/chat_data_source.dart';
export 'src/chat_scroll/chat_mutations.dart';
export 'src/chat_scroll/chat_scroll_common.dart';
export 'src/chat_scroll/chat_scroll_controller.dart';
export 'src/chat_scroll/chat_scroll_events.dart';
export 'src/chat_scroll/chat_selection_controller.dart';
export 'src/chat_scroll/chat_sender_run_layout.dart';
export 'src/chat_widgets/chat_bubble_metrics.dart';
export 'src/chat_widgets/chat_dated_message.dart';
export 'src/chat_widgets/chat_keyboard_shortcuts.dart';
export 'src/chat_widgets/chat_message_body.dart';
export 'src/chat_widgets/chat_message_theme.dart';
export 'src/chat_widgets/chat_scroll_theme.dart';
export 'src/chat_widgets/chat_scroll_view.dart';
export 'src/chat_widgets/chat_scrollbar.dart';
export 'src/chat_widgets/chat_selectable_message.dart';
export 'src/chat_widgets/chat_selection_chrome.dart';
export 'src/chat_widgets/chat_selection_theme.dart';
export 'src/chat_widgets/message_menu/chat_message_menu.dart';
export 'src/chat_widgets/message_menu/chat_pre_ime_back.dart';
