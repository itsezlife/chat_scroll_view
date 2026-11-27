/// Message media display: the message media policy that lays a message's
/// media items out into blocks, and the geometry it is built on.
///
/// Owns: [MessageMediaPolicy] and its layout step ([MediaLayoutStep], the
/// default [MediaLayoutPolicy] with its box sizing, mosaic algorithm slot,
/// fit modes and file stack [MediaFileStackPolicy]), the [MediaLayout] value it returns (blocks of cells keyed
/// by `MediaItemId`, each corner's radius resolved by [MediaCornerPolicy]),
/// its paint step ([MessageMediaView] and the replaceable
/// [MediaCellBuilders], drawing through the asset pipeline, and the
/// [MediaChromeSlots] over them: the time pill's rect, the info badge, the
/// status control, the spoiler and its reveal, the options affordance), the
/// geometry
/// under it (the single box size
/// [computeSingleMediaSize], the default mosaic [GroupedMessages] and
/// [MosaicLayout], [MediaLayoutMetrics]), what a chat's items remember while
/// it is open ([MessageMediaState]), and the part a body part hit is on
/// ([MessageMediaHitPart]), and how a change of the layout animates
/// ([MediaLayout.lerp], [MediaTransitionPolicy] and the per-message clock
/// [MessageMediaTransition]).
library;

export 'src/chrome/media_cell_chrome.dart' show MediaControlsScope;
export 'src/chrome/media_chrome_slots.dart';
export 'src/chrome/media_options_affordance.dart';
export 'src/chrome/media_spoiler_cover.dart';
export 'src/chrome/media_spoiler_reveal.dart';
export 'src/chrome/media_time_pill.dart';
export 'src/diagnostics/media_op.dart';
export 'src/grouped_message_position.dart';
export 'src/grouped_messages.dart';
export 'src/layout/media_corner_radii.dart';
export 'src/layout/media_file_row.dart';
export 'src/layout/media_layout.dart';
export 'src/layout/media_layout_input.dart';
export 'src/media_layout_metrics.dart';
export 'src/message_media_hit_part.dart';
export 'src/mosaic_layout.dart';
export 'src/paint/media_box_cell.dart';
export 'src/paint/media_cell_builders.dart';
export 'src/paint/media_row_cell.dart';
export 'src/paint/message_media_view.dart';
export 'src/paint/middle_elided_text.dart';
export 'src/policy/desktop_mosaic_algorithm.dart';
export 'src/policy/ios_mosaic_algorithm.dart';
export 'src/policy/media_autoplay_policy.dart';
export 'src/policy/media_box_sizing.dart';
export 'src/policy/media_corner_policy.dart';
export 'src/policy/media_file_stack_policy.dart';
export 'src/policy/media_file_strings.dart';
export 'src/policy/media_file_text.dart';
export 'src/policy/media_layout_policy.dart';
export 'src/policy/message_media_policy.dart';
export 'src/policy/mosaic_algorithm.dart';
export 'src/single_media_layout.dart';
export 'src/state/media_state_op.dart';
export 'src/state/message_media_state.dart';
export 'src/state/message_media_state_scope.dart';
export 'src/transition/media_layout_transition.dart';
export 'src/transition/media_transition_policy.dart';
export 'src/transition/message_media_transition.dart';
