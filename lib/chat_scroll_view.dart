/// Endless, anchor-based chat viewport.
///
/// Layout fans out from `(anchorMessageId, anchorPixelOffset)` rather than a
/// global content height. Integrate by implementing [ChatDataSource] and
/// embedding [ChatScrollView].
///
/// Host-facing helpers include [DatedMessage] (day separator + body),
/// [ChatMessageBody] (in-bubble content + meta last-line packing),
/// [ChatMessageChangeTransition] (edit morph: layout-final + paint deltas),
/// [ChatBubbleMetrics] (theme + run → corner / padding resolvers), and
/// [ChatBodyLinkify] (host-invoked bare URL / mention → markdown; never paint).
library;

export 'package:flutter_md/flutter_md.dart'
    show
        Markdown,
        MarkdownSelection,
        MarkdownPosition;

export 'src/chat_scroll/animate_to_busy_policy.dart';
export 'src/chat_scroll/animate_to_disposition.dart';
export 'src/chat_scroll/animate_to_load_policy.dart';
export 'src/chat_scroll/chat_body_linkify.dart';
export 'src/chat_scroll/chat_data_source.dart';
export 'src/chat_scroll/chat_mutations.dart';
export 'src/chat_scroll/chat_scroll_common.dart';
export 'src/chat_scroll/chat_scroll_controller.dart';
export 'src/chat_scroll/chat_scroll_events.dart';
export 'src/chat_scroll/chat_selection_allowed.dart';
export 'src/chat_scroll/chat_selection_controller.dart';
export 'src/chat_scroll/chat_selection_interaction.dart';
export 'src/chat_scroll/chat_selection_policy.dart';
export 'src/chat_scroll/chat_sender_run_layout.dart';
export 'src/chat_widgets/chat_bubble_metrics.dart';
export 'src/chat_widgets/chat_code_block_painter.dart';
export 'src/chat_widgets/chat_dated_message.dart';
export 'src/chat_widgets/chat_keyboard_shortcuts.dart';
export 'src/chat_widgets/chat_markdown_autoscroll.dart';
export 'src/chat_widgets/chat_markdown_body.dart';
export 'src/chat_widgets/chat_message_body.dart';
export 'src/chat_widgets/chat_message_change_transition.dart';
export 'src/chat_widgets/chat_message_surface_bounds.dart';
export 'src/chat_widgets/chat_message_theme.dart';
export 'src/chat_widgets/chat_scroll_theme.dart';
export 'src/chat_widgets/chat_scroll_view.dart';
export 'src/chat_widgets/chat_scrollbar.dart';
export 'src/chat_widgets/chat_secondary_message_tap_scope.dart';
export 'src/chat_widgets/chat_selectable_message.dart';
export 'src/chat_widgets/chat_selection_chrome.dart';
export 'src/chat_widgets/chat_selection_metrics.dart';
export 'src/chat_widgets/chat_selection_theme.dart';
export 'src/chat_widgets/chat_smooth_contour.dart';
export 'src/chat_widgets/chat_span_feedback.dart';
export 'src/chat_widgets/chat_tap_highlight.dart';
export 'src/chat_widgets/message_menu/chat_message_menu.dart';
export 'src/chat_widgets/message_menu/chat_pre_ime_back.dart';
