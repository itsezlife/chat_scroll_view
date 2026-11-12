/// The keyboard scroll keys of a viewport.
///
/// **Seam:** [ViewportScrollKeys] over a focused child, driven by key
/// presses; observed through the scroll requests it makes.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

void main() {
  late List<Object> calls;
  late FocusNode focus;

  setUp(() {
    calls = [];
    focus = FocusNode();
    addTearDown(focus.dispose);
  });

  Future<void> pump(
    WidgetTester tester, {
    double height = 400,
    double? pageExtent,
    bool ends = true,
    Map<ShortcutActivator, Intent>? inner,
  }) async {
    Widget child = Focus(
      focusNode: focus,
      autofocus: true,
      child: const SizedBox.expand(),
    );
    if (inner != null) {
      child = Shortcuts(
        shortcuts: inner,
        child: Actions(
          actions: <Type, Action<Intent>>{_Probe: _ProbeAction()},
          child: child,
        ),
      );
    }
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: height,
            width: 300,
            child: ViewportScrollKeys(
              onScrollBy: calls.add,
              onScrollToStart: ends ? () => calls.add('start') : null,
              onScrollToEnd: ends ? () => calls.add('end') : null,
              pageExtent: pageExtent,
              child: child,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the arrows step a line toward the end or the start', (
    tester,
  ) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);

    expect(calls, [60.0, -60.0]);
  });

  testWidgets('the page keys step most of the measured height', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);

    expect(calls, [400 * 0.85, -400 * 0.85]);
  });

  testWidgets('a page extent overrides the measured one', (tester) async {
    await pump(tester, pageExtent: 100);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);

    expect(calls, [100.0]);
  });

  testWidgets('Home and End go to the ends', (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);

    expect(calls, ['start', 'end']);
  });

  testWidgets('without ends, Home and End are left to others', (tester) async {
    await pump(tester, ends: false);

    final handled = await tester.sendKeyEvent(LogicalKeyboardKey.home);

    expect(handled, isFalse);
    expect(calls, isEmpty);
  });

  testWidgets('a binding below wins, and one it leaves disabled comes here', (
    tester,
  ) async {
    var enabled = true;
    await pump(
      tester,
      inner: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): _Probe(
          () => enabled,
          () => calls.add('inner'),
        ),
      },
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    enabled = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

    expect(calls, ['inner', 60.0]);
  });
}

// An intent that carries its own action, enabled while [enabled] says so.
class _Probe extends Intent {
  const _Probe(this.enabled, this.run);

  final bool Function() enabled;
  final VoidCallback run;
}

class _ProbeAction extends ContextAction<_Probe> {
  @override
  bool isEnabled(_Probe intent, [BuildContext? context]) => intent.enabled();

  @override
  Object? invoke(_Probe intent, [BuildContext? context]) {
    intent.run();
    return null;
  }
}
