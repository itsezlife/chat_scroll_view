/// The attach model: what a picker front-end shares on every platform.
///
/// An `AttachSelection` of `AttachItem`s under the host's `AttachLimits` and
/// a platform's `AttachPolicy`. Pure Dart: no Flutter, no platform code, no
/// media package.
library;

export 'src/item/attach_item.dart';
export 'src/item/attach_limits.dart';
export 'src/policy/attach_policy.dart';
export 'src/selection/attach_selection.dart';
