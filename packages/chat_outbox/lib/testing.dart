/// Fakes for tests of `chat_outbox` and of the hosts that drive an outbox:
/// the home of a recording sender, a fake id strategy and a fake transfer
/// engine as the paths that need them land.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;
