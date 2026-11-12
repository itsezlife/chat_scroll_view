/// Fakes and contract suites for tests of `bulletins` and of hosts and
/// policies built on it.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/testing/bulletin_policy_contract.dart';
export 'src/testing/manual_bulletin_clock.dart';
