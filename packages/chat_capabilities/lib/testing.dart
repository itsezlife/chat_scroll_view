/// Fakes for tests of `chat_capabilities` and of the consumers that read a
/// chat's capabilities.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/testing/fake_chat_capabilities_source.dart';
export 'src/testing/recording_capability_feedback.dart';
