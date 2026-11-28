/// Fakes and contract suites for tests of `chat_outbox` and of the hosts
/// that drive an outbox: a transfer engine with scripted publish jobs, the
/// id strategy contract with a fake tail target and a fake id strategy,
/// and a recording sender with scripted answers.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/testing/fake_outbox_transfers.dart';
export 'src/testing/fake_outgoing_id_strategy.dart';
export 'src/testing/fake_outgoing_tail.dart';
export 'src/testing/outgoing_id_strategy_contract.dart';
export 'src/testing/recording_outgoing_sender.dart';
