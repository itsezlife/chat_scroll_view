import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  group('against ObservableNotifier', () {
    runObservableContract(() {
      final notifier = ObservableNotifier();
      return ObservableHarness(
        observable: notifier,
        signal: notifier.notify,
        dispose: notifier.dispose,
      );
    });
  });

  group('against ObservableValue', () {
    runObservableContract(() {
      final value = ObservableValue(0);
      return ObservableHarness(
        observable: value,
        signal: () => value.value++,
        dispose: value.dispose,
      );
    });
  });

  group('against FakeObservable', () {
    runObservableContract(() {
      final fake = FakeObservable();
      return ObservableHarness(
        observable: fake,
        signal: fake.signal,
        dispose: fake.dispose,
      );
    });
  });

  group('FakeObservable', () {
    test('counts its listeners', () {
      final fake = FakeObservable();
      void listener() {}

      fake
        ..addListener(listener)
        ..addListener(listener);
      expect(fake.listenerCount, 1);

      fake.removeListener(listener);
      expect(fake.listenerCount, 0);
    });

    test('has no listeners once disposed', () {
      final fake = FakeObservable()..addListener(() {});

      fake.dispose();

      expect(fake.listenerCount, 0);
      expect(fake.isDisposed, isTrue);
    });
  });
}
