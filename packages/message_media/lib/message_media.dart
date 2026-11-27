/// Message media display: the message media policy that lays a message's
/// media items out into blocks, and the geometry it is built on.
///
/// Owns: [MessageMediaPolicy] and its layout step ([MediaLayoutStep], the
/// default [MediaLayoutPolicy] with its box sizing, mosaic algorithm slot
/// and fit modes), the [MediaLayout] value it returns (blocks of cells keyed
/// by `MediaItemId`), and the geometry under it: the single box size
/// ([computeSingleMediaSize]), the default mosaic ([GroupedMessages],
/// [MosaicLayout]) and [MediaLayoutMetrics].
library;

export 'src/diagnostics/media_op.dart';
export 'src/grouped_message_position.dart';
export 'src/grouped_messages.dart';
export 'src/layout/media_layout.dart';
export 'src/layout/media_layout_input.dart';
export 'src/media_layout_metrics.dart';
export 'src/mosaic_layout.dart';
export 'src/policy/media_box_sizing.dart';
export 'src/policy/media_layout_policy.dart';
export 'src/policy/message_media_policy.dart';
export 'src/policy/mosaic_algorithm.dart';
export 'src/single_media_layout.dart';
