/// Endless, anchor-based chat viewport.
///
/// Layout fans out from `(anchorMessageId, anchorPixelOffset)` rather than a
/// global content height. Integrate by implementing [ChatDataSource] and
/// embedding [ChatScrollView].
library;

export 'src/chat_scroll/chat_data_source.dart';
export 'src/chat_scroll/chat_mutations.dart';
export 'src/chat_scroll/chat_scroll_common.dart';
export 'src/chat_scroll/chat_scroll_controller.dart';
export 'src/chat_scroll/chat_scroll_events.dart';
export 'src/chat_scroll/chat_selection_controller.dart';
export 'src/chat_scroll/chat_sender_run_layout.dart';
export 'src/chat_widgets/chat_dated_message.dart';
export 'src/chat_widgets/chat_keyboard_shortcuts.dart';
export 'src/chat_widgets/chat_message_theme.dart';
export 'src/chat_widgets/chat_scroll_theme.dart';
export 'src/chat_widgets/chat_scroll_view.dart';
export 'src/chat_widgets/chat_scrollbar.dart';
export 'src/chat_widgets/chat_selectable_message.dart';
export 'src/chat_widgets/chat_selection_chrome.dart';
export 'src/chat_widgets/chat_selection_theme.dart';
