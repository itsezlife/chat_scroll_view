/// Message media display: the geometry a message media policy lays media
/// items out with.
///
/// Owns: the single box size ([computeSingleMediaSize]), the mosaic
/// algorithm ([GroupedMessages.calculate], [GroupedMessagePosition]) and its
/// pixel projection ([MosaicLayout]), every cell addressed by its media
/// item's id (`MediaItemId`), and the layout constants ([MediaLayoutMetrics]).
library;

export 'src/grouped_message_position.dart';
export 'src/grouped_messages.dart';
export 'src/media_layout_metrics.dart';
export 'src/mosaic_layout.dart';
export 'src/single_media_layout.dart';
