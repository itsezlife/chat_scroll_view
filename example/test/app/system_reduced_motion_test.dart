import 'package:chat_scroll_view_example/src/app/system_reduced_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);

  test('starts at what the system says now', () {
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;

    final setting = SystemReducedMotion();
    addTearDown(setting.dispose);

    expect(setting.value, isTrue);
  });

  test('follows the system setting both ways', () {
    final setting = SystemReducedMotion();
    addTearDown(setting.dispose);
    final heard = <bool>[];
    setting.addListener(() => heard.add(setting.value));
    expect(setting.value, isFalse);

    binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    binding.platformDispatcher.clearAccessibilityFeaturesTestValue();

    expect(heard, [true, false], reason: 'told on a change only');
  });

  test('a disposed setting is no longer told, and disposing twice is '
      'harmless', () {
    final setting = SystemReducedMotion()
      ..dispose()
      ..dispose();

    binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;

    expect(setting.value, isFalse);
  });
}
