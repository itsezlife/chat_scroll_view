/// Message media display: the geometry a message media policy lays media
/// items out with.
///
/// Owns: the single box size ([computeSingleMediaSize]), the mosaic
/// algorithm ([GroupedMessages.calculate], [GroupedMessagePosition]) and its
/// pixel projection ([MosaicLayout]), every cell addressed by its media
/// item's id (`MediaItemId`), the layout constants ([MediaLayoutMetrics]),
/// what a chat's items remember while it is open ([MessageMediaState]), and
/// the part a body part hit is on ([MessageMediaHitPart]).
library;

export 'src/grouped_message_position.dart';
export 'src/grouped_messages.dart';
export 'src/media_layout_metrics.dart';
export 'src/message_media_hit_part.dart';
export 'src/mosaic_layout.dart';
export 'src/single_media_layout.dart';
export 'src/state/media_state_op.dart';
export 'src/state/message_media_state.dart';
export 'src/state/message_media_state_scope.dart';
