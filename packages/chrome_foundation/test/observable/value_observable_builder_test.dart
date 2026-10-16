/// The one bridge from a model observable to the widget tree.
///
/// **Seam:** `ValueObservableBuilder` mounted over an `ObservableValue`, seen
/// through the widgets it builds and the listeners left on the observable.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ObservableValue<int> value;

  setUp(() => value = ObservableValue<int>(1));
  tearDown(() => value.dispose());

  Widget host(ValueObservable<int> observable, {List<int>? builds}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueObservableBuilder<int>(
          observable: observable,
          builder: (context, current) {
            builds?.add(current);
            return Text('$current');
          },
        ),
      );

  testWidgets('builds the current value and rebuilds when it changes', (
    tester,
  ) async {
    await tester.pumpWidget(host(value));
    expect(find.text('1'), findsOneWidget);

    value.value = 2;
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('follows another observable when the widget is given one', (
    tester,
  ) async {
    final other = ObservableValue<int>(10);
    addTearDown(other.dispose);
    await tester.pumpWidget(host(value));

    await tester.pumpWidget(host(other));
    expect(find.text('10'), findsOneWidget);
    value.value = 3;
    await tester.pump();
    expect(find.text('10'), findsOneWidget, reason: 'the old one is left');

    other.value = 11;
    await tester.pump();
    expect(find.text('11'), findsOneWidget);
  });

  testWidgets('leaves no listener behind when it is removed', (tester) async {
    final counted = _Counted(value);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueObservableBuilder<int>(
          observable: counted,
          builder: (context, current) => Text('$current'),
        ),
      ),
    );
    expect(counted.listenerCount, 1);

    await tester.pumpWidget(const SizedBox());

    expect(counted.listenerCount, 0);
  });

  testWidgets('a change published from layout rebuilds after the frame, '
      'not inside it', (tester) async {
    final builds = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            host(value, builds: builds),
            _PublishesInLayout(() => value.value = 7),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.pump();

    expect(find.text('7'), findsOneWidget);
    expect(builds.last, 7);
  });
}

/// An observable that follows [_value] and counts the listeners it was given.
final class _Counted implements ValueObservable<int> {
  _Counted(this._value);

  final ValueObservable<int> _value;
  int listenerCount = 0;

  @override
  int get value => _value.value;

  @override
  void addListener(ObservableListener listener) {
    listenerCount++;
    _value.addListener(listener);
  }

  @override
  void removeListener(ObservableListener listener) {
    listenerCount--;
    _value.removeListener(listener);
  }
}

/// A box that publishes a change while it lays out, as a view reporting its
/// extent does.
final class _PublishesInLayout extends SingleChildRenderObjectWidget {
  const _PublishesInLayout(this.publish);

  final void Function() publish;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPublishes(publish);
}

final class _RenderPublishes extends RenderBox {
  _RenderPublishes(this._publish);

  final void Function() _publish;
  bool _done = false;

  @override
  void performLayout() {
    size = constraints.constrain(const Size(10, 10));
    if (!_done) {
      _done = true;
      _publish();
    }
  }
}
