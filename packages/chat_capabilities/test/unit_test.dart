/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:test/test.dart';

import 'capability/capability_test.dart' as capability_test;
import 'chat_capabilities_test.dart' as chat_capabilities_test;
import 'diagnostics/capabilities_diagnostics_test.dart'
    as capabilities_diagnostics_test;
import 'group/slow_mode_test.dart' as slow_mode_test;
import 'listenable/select_test.dart' as select_test;

void main() {
  group('capability/capability_test.dart', capability_test.main);
  group('chat_capabilities_test.dart', chat_capabilities_test.main);
  group(
    'diagnostics/capabilities_diagnostics_test.dart',
    capabilities_diagnostics_test.main,
  );
  group('group/slow_mode_test.dart', slow_mode_test.main);
  group('listenable/select_test.dart', select_test.main);
}
