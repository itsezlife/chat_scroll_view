/// Fakes and contract suites for tests of `chat_outbox` and of the hosts
/// that drive an outbox: the id strategy contract, a fake tail target and a
/// fake id strategy, with a recording sender and a fake transfer engine as
/// the paths that need them land.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/testing/fake_outgoing_id_strategy.dart';
export 'src/testing/fake_outgoing_tail.dart';
export 'src/testing/outgoing_id_strategy_contract.dart';
