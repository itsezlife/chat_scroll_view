import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  test('starts at its initial value', () {
    expect(ObservableValue(3).value, 3);
  });

  group('setting the value', () {
    test('notifies listeners, who read the new value', () {
      final observable = ObservableValue(1);
      final seen = <int>[];
      observable
        ..addListener(() => seen.add(observable.value))
        ..value = 2
        ..value = 3;
      expect(seen, [2, 3]);
    });

    test('stays silent when the new value equals the current one', () {
      final observable = ObservableValue(4);
      var calls = 0;
      observable
        ..addListener(() => calls++)
        ..value = 4;
      expect(calls, 0);
    });

    test('compares with ==, so equal snapshots do not signal', () {
      final observable = ObservableValue(
        const Collection(id: CollectionId.recent),
      );
      var calls = 0;
      observable
        ..addListener(() => calls++)
        ..value = const Collection(id: CollectionId.recent)
        ..value = const Collection(
          id: CollectionId.recent,
          contents: CollectionContents.loading,
        );
      expect(calls, 1);
    });
  });

  group('batch', () {
    test('delivers one signal and only the final value', () {
      final observable = ObservableValue(0);
      final seen = <int>[];
      observable
        ..addListener(() => seen.add(observable.value))
        ..batch(() {
          observable
            ..value = 1
            ..value = 2
            ..value = 3;
        });
      expect(seen, [3]);
    });

    test('stays silent when no assignment changed anything', () {
      final observable = ObservableValue(5);
      var calls = 0;
      observable
        ..addListener(() => calls++)
        ..batch(() => observable.value = 5);
      expect(calls, 0);
    });
  });

  group('after dispose', () {
    test('keeps the latest value readable but never signals', () {
      final observable = ObservableValue(1);
      var calls = 0;
      observable
        ..addListener(() => calls++)
        ..dispose()
        ..value = 2;
      expect(observable.value, 2);
      expect(calls, 0);
      expect(observable.isDisposed, isTrue);
    });
  });

  test('is a ValueObservable that exposes no way to signal', () {
    final ValueObservable<int> readOnly = ObservableValue(1);
    expect(readOnly.value, 1);
    expect(readOnly, isNot(isA<ObservableNotifier>()));
  });
}
