/// The attach model: what a picker front-end shares on every platform.
///
/// An `AttachSelection` of `AttachItem`s under the host's `AttachLimits` and
/// a platform's `AttachPolicy`; `planSend` cuts a `SendRequest` into a
/// `SendPlan`; `SendOptionVisibility` says which options to offer and
/// `SendOptionStore` remembers them. Pure Dart: no Flutter, no platform
/// code, no media package.
library;

export 'src/item/attach_item.dart';
export 'src/item/attach_limits.dart';
export 'src/policy/attach_policy.dart';
export 'src/selection/attach_selection.dart';
export 'src/send/send_option_visibility.dart';
export 'src/send/send_options.dart';
export 'src/send/send_plan.dart';
export 'src/store/send_option_store.dart';
