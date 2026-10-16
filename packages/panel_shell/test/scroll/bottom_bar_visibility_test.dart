import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

void main() {
  late BottomBarVisibility visibility;

  setUp(() => visibility = BottomBarVisibility());
  tearDown(() => visibility.dispose());

  test('starts shown', () {
    expect(visibility.visible.value, isTrue);
  });

  group('drag and fling', () {
    test('hides after the content moved the toggle offset toward its end', () {
      visibility
        ..apply(const PageScrollDrag(20))
        ..apply(const PageScrollFling(10));
      expect(visibility.visible.value, isTrue);

      visibility.apply(const PageScrollFling(8));
      expect(visibility.visible.value, isFalse);
    });

    test('shows again after the content moved the offset back', () {
      visibility
        ..apply(const PageScrollDrag(40))
        ..apply(const PageScrollDrag(-20));
      expect(visibility.visible.value, isFalse);

      visibility.apply(const PageScrollDrag(-20));
      expect(visibility.visible.value, isTrue);
    });

    test('counts the net distance and forgets a count against the bar', () {
      visibility
        ..apply(const PageScrollDrag(30))
        ..apply(const PageScrollDrag(-40))
        ..apply(const PageScrollDrag(30));

      // The bar is shown, so the net -10 pointed the way it already points
      // and was dropped; 30 more is still below 38.
      expect(visibility.visible.value, isTrue);
    });

    test('uses the configured offset', () {
      final small = BottomBarVisibility(toggleOffset: 10)
        ..apply(const PageScrollDrag(10));
      addTearDown(small.dispose);

      expect(small.visible.value, isFalse);
    });
  });

  group('jump and idle', () {
    test('a programmatic jump shows the bar and forgets the distance', () {
      visibility
        ..apply(const PageScrollDrag(40))
        ..apply(const PageScrollJump());
      expect(visibility.visible.value, isTrue);

      visibility.apply(const PageScrollDrag(20));
      expect(visibility.visible.value, isTrue);
    });

    test('idle at an edge shows the bar', () {
      visibility
        ..apply(const PageScrollDrag(40))
        ..apply(const PageScrollIdle(atEdge: true));

      expect(visibility.visible.value, isTrue);
    });

    test('idle away from an edge leaves the bar as it is', () {
      visibility
        ..apply(const PageScrollDrag(40))
        ..apply(const PageScrollIdle());

      expect(visibility.visible.value, isFalse);
    });
  });

  group('pinned hidden', () {
    test(
      'hides the bar for as long as it is set, whatever the scroll does',
      () {
        visibility.pinnedHidden = true;
        expect(visibility.visible.value, isFalse);

        visibility.apply(const PageScrollJump());
        expect(visibility.visible.value, isFalse);
      },
    );

    test('releasing the pin shows the bar again', () {
      visibility
        ..pinnedHidden = true
        ..pinnedHidden = false;

      expect(visibility.visible.value, isTrue);
    });
  });

  group('show', () {
    test('shows the bar and forgets the distance', () {
      visibility
        ..apply(const PageScrollDrag(40))
        ..show();

      expect(visibility.visible.value, isTrue);
    });
  });

  test('signals only when the visibility changes', () {
    var signals = 0;
    visibility.visible.addListener(() => signals++);

    visibility
      ..apply(const PageScrollDrag(10))
      ..apply(const PageScrollDrag(40))
      ..apply(const PageScrollDrag(40))
      ..show()
      ..show();

    expect(signals, 2);
  });
}
