/// Chat capabilities: what the user may do in one chat, as outcomes with
/// denial reasons, group by group.
///
/// The host resolves its rights into a `ChatCapabilities` value per chat and
/// passes a `ValueListenable` of it to each consumer, which reads its group
/// through `select`. No value means everything is allowed with the default
/// limits. Pure Dart: no Flutter.
library;

export 'src/capability/capability.dart';
export 'src/chat_capabilities.dart';
export 'src/diagnostics/capabilities_op.dart';
export 'src/flags/media_kind.dart';
export 'src/flags/protection_flags.dart';
export 'src/group/chat_limits.dart';
export 'src/group/chat_protection.dart';
export 'src/group/sendable_media.dart';
export 'src/group/sending_capabilities.dart';
export 'src/group/slow_mode.dart';
export 'src/group/write_access.dart';
export 'src/listenable/chat_capabilities_listenable.dart';
