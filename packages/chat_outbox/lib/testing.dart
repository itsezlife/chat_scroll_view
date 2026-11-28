/// Fakes for tests of `chat_outbox` and of the hosts that drive an outbox:
/// a transfer engine with scripted publish jobs, and, as the paths that
/// need them land, a recording sender and a fake id strategy.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/testing/fake_outbox_transfers.dart';
