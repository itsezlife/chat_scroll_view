/// Telegram-faithful single and grouped photo/video layout geometry.
///
/// Owns: single-media size clamps, [GroupedMessages.calculate] /
/// [GroupedMessagePosition], mosaic pixel projection, and muted placeholder
/// paint.
library;

export 'src/grouped_message_position.dart';
export 'src/grouped_messages.dart';
export 'src/media_kind.dart';
export 'src/media_layout_metrics.dart';
export 'src/message_media_placeholder.dart';
export 'src/mosaic_layout.dart';
export 'src/single_media_layout.dart';
