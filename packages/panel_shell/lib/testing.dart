/// Fakes and rules for tests of `panel_shell` and of the pages built on it.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/testing/fake_page_controller_registry.dart';
export 'src/testing/fake_panel_announcer.dart';
export 'src/testing/fake_panel_page.dart';
export 'src/testing/page_controller_registry_contract.dart';
export 'src/testing/panel_semantics_rule.dart';
export 'src/testing/panel_shell_test_scope.dart';
