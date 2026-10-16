/// Fakes and contract suites for tests of `panel_presentation` and of the
/// strategies built on it.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/testing/fake_ime_input.dart';
export 'src/testing/fake_presentation_strategy.dart';
export 'src/testing/ime_input_port_contract.dart';
export 'src/testing/manual_panel_clock.dart';
export 'src/testing/presentation_policy_contract.dart';
