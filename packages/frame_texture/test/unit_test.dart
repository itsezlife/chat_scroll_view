/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not).
library;

import 'package:flutter_test/flutter_test.dart';

import 'platform_host_contract_test.dart' as platform_host_contract_test;
import 'platform_host_test.dart' as platform_host_test;
import 'texture_table_test.dart' as texture_table_test;

void main() {
  group('platform_host_contract_test.dart', platform_host_contract_test.main);
  group('platform_host_test.dart', platform_host_test.main);
  group('texture_table_test.dart', texture_table_test.main);
}
