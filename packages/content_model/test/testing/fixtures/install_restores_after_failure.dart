/// Run in a process of its own by `recording_diagnostics_test.dart`: its
/// first test fails on purpose, so it is not part of `unit_test.dart`.
library;

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  final original = ChatDiagnostics.current;

  test('installs a recorder and fails', () {
    RecordingDiagnostics.install();
    fail('failing on purpose');
  });

  test('restored after failure', () {
    expect(ChatDiagnostics.current, same(original));
  });
}
