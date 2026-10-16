import 'package:chat_composer/chat_composer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ComposerController composer;

  setUp(() => composer = ComposerController());
  tearDown(() => composer.dispose());

  group('extent', () {
    test('is zero before the view reports', () {
      expect(composer.extent.value, 0);
    });

    test('publishes what the view reports and signals each change', () {
      var signals = 0;
      composer.extent.addListener(() => signals++);

      composer.reportExtent(72);
      composer.reportExtent(72);
      composer.reportExtent(96);

      expect(composer.extent.value, 96);
      expect(signals, 2);
    });

    test('ignores reports after dispose', () {
      composer.dispose();

      composer.reportExtent(10);

      expect(composer.extent.value, 0);
    });
  });
}
