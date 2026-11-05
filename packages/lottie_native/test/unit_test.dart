/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not).
library;

import 'package:flutter_test/flutter_test.dart';

import 'fake_lottie_binding_contract_test.dart'
    as fake_lottie_binding_contract_test;
import 'fake_lottie_binding_test.dart' as fake_lottie_binding_test;
import 'hook_build_test.dart' as hook_build_test;
import 'lottie_features_test.dart' as lottie_features_test;
import 'native_binding_contract_test.dart' as native_binding_contract_test;
import 'native_lottie_binding_test.dart' as native_lottie_binding_test;

void main() {
  group(
    'fake_lottie_binding_contract_test.dart',
    fake_lottie_binding_contract_test.main,
  );
  group('fake_lottie_binding_test.dart', fake_lottie_binding_test.main);
  group('hook_build_test.dart', hook_build_test.main);
  group('lottie_features_test.dart', lottie_features_test.main);
  group('native_binding_contract_test.dart', native_binding_contract_test.main);
  group('native_lottie_binding_test.dart', native_lottie_binding_test.main);
}
