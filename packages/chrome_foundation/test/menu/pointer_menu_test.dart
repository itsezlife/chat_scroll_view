/// The pointer menu: a popup list opened at the pointer, driven by the mouse
/// and the keyboard.
///
/// **Seam:** `PointerMenu.show` over a real overlay, read through laid-out
/// rects, the semantics tree, the focus tree and a fake clock; the pointer is
/// a mouse `TestGesture`, never a tap helper, because hover is the point.
library;

import 'dart:ui' show Tristate;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = Size(800, 600);

List<PointerMenuEntry> _entries(List<String> chosen) {
  PointerMenuItem item(
    String id,
    String label, {
    String? hint,
    bool enabled = true,
  }) => PointerMenuItem(
    id: id,
    label: label,
    hint: hint,
    enabled: enabled,
    onSelected: () => chosen.add(id),
  );
  return [
    item('undo', '&Undo', hint: 'Ctrl+Z'),
    item('redo', '&Redo', hint: 'Ctrl+Y', enabled: false),
    const PointerMenuSeparator(),
    item('cut', 'Cu&t', hint: 'Ctrl+X'),
    item('copy', '&Copy', hint: 'Ctrl+C'),
    PointerMenuItem(
      id: 'format',
      label: 'Formatting',
      submenu: [
        item('bold', 'Bold', hint: 'Ctrl+B'),
        item('italic', 'Italic', enabled: false),
        item('underline', 'Underline'),
      ],
    ),
    item('all', 'Select All', hint: 'Ctrl+A'),
  ];
}

final class _Rig {
  _Rig(this.tester, this.handle, this.chosen, this.mouse);

  final WidgetTester tester;
  final PointerMenuHandle handle;
  final List<String> chosen;
  final TestGesture mouse;

  static int underlyingTaps = 0;

  static Future<_Rig> open(
    WidgetTester tester, {
    Offset at = const Offset(100, 100),
    Size screen = _screen,
    ChromeMotionData motion = const ChromeMotionData(
      speed: ChromeMotionSpeed.instant,
    ),
    TextDirection direction = TextDirection.ltr,
    List<PointerMenuEntry>? entries,
    FocusNode? focusParent,
    FocusNode? returnFocusTo,
    Widget? above,
    FocusNode? focused,
  }) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    underlyingTaps = 0;
    final chosen = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => underlyingTaps++,
                ),
              ),
              ?above,
            ],
          ),
        ),
      ),
    );
    if (focused != null) {
      focused.requestFocus();
      await tester.pump();
    }
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    final handle = PointerMenu.show(
      tester.element(find.byType(Scaffold)),
      globalPosition: at,
      entries: entries ?? _entries(chosen),
      tokens: PointerMenuTokens.referenceDay,
      motion: motion,
      textDirection: direction,
      focusParent: focusParent,
      returnFocusTo: returnFocusTo,
    );
    await tester.pump();
    await tester.pump();
    return _Rig(tester, handle, chosen, mouse);
  }

  Rect panel([int level = 0]) =>
      tester.getRect(find.byKey(PointerMenuPanelKey(level)));

  Finder row(String id) => find.byKey(PointerMenuRowKey(id));

  Offset center(String id) => tester.getCenter(row(id));

  Offset _at = Offset.zero;

  /// Moves the mouse to [to] in steps, so the pointer guard is satisfied.
  Future<void> glideTo(Offset to) async {
    final from = _at == Offset.zero ? const Offset(100, 100) : _at;
    for (var i = 1; i <= 8; i++) {
      await mouse.moveTo(Offset.lerp(from, to, i / 8)!);
    }
    _at = to;
    await tester.pump();
  }

  bool selected(String id) =>
      tester.getSemantics(row(id)).flagsCollection.isSelected ==
      Tristate.isTrue;

  Future<void> key(LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  Future<void> settle() => tester.pumpAndSettle();
}

void main() {
  group('placement', () {
    testWidgets('the body sits 5 px right of the pointer, level with it', (
      tester,
    ) async {
      final rig = await _Rig.open(tester);

      expect(rig.panel().topLeft, const Offset(105, 100));
    });

    testWidgets('rows are 33 px, separators 11, padding 8 above and below', (
      tester,
    ) async {
      final rig = await _Rig.open(tester);

      final panel = rig.panel();
      expect(panel.height, 8 + 6 * 33 + 11 + 8);
      expect(rig.tester.getRect(rig.row('undo')).top, panel.top + 8);
      expect(rig.tester.getRect(rig.row('undo')).height, 33);
      expect(rig.tester.getRect(rig.row('cut')).top, panel.top + 8 + 66 + 11);
    });

    testWidgets('the width is the widest row, clamped to 156..300', (
      tester,
    ) async {
      // The test font draws every glyph 13 px wide, a hint included.
      final rig = await _Rig.open(tester);

      // 'Select All' + 'Ctrl+A': 17 + 10 * 13 + 6 + 6 * 13 + 17 = 248.
      expect(rig.panel().width, 248);
    });

    testWidgets('a short menu is 156 wide', (tester) async {
      final rig = await _Rig.open(
        tester,
        entries: [PointerMenuItem(id: 'a', label: 'A', onSelected: () {})],
      );

      expect(rig.panel().width, 156);
    });

    testWidgets('flips left and up at the screen corner', (tester) async {
      final rig = await _Rig.open(tester, at: const Offset(780, 580));

      final panel = rig.panel();
      expect(panel.right, 775);
      expect(panel.bottom, 580);
    });

    testWidgets('mirrors in right-to-left', (tester) async {
      final rig = await _Rig.open(
        tester,
        at: const Offset(400, 100),
        direction: TextDirection.rtl,
      );

      expect(rig.panel().right, 395);
    });
  });

  group('rows', () {
    testWidgets('nothing is selected on open', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(tester);

      for (final id in ['undo', 'cut', 'copy', 'format', 'all']) {
        expect(rig.selected(id), isFalse, reason: id);
      }
      handle.dispose();
    });

    testWidgets('a hovered row takes the highlight', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(tester);

      await rig.glideTo(rig.center('cut'));

      expect(rig.selected('cut'), isTrue);
      expect(rig.selected('copy'), isFalse);
      handle.dispose();
    });

    testWidgets('a row that cannot be chosen takes no highlight', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(tester);

      await rig.glideTo(rig.center('redo'));

      expect(rig.selected('redo'), isFalse);
      handle.dispose();
    });

    testWidgets('leaving a row clears the highlight', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(tester);
      await rig.glideTo(rig.center('cut'));

      await rig.mouse.moveTo(const Offset(700, 500));
      await tester.pump();

      expect(rig.selected('cut'), isFalse);
      handle.dispose();
    });

    testWidgets(
      'the label is spoken without its mnemonic mark, with its hint',
      (tester) async {
        final handle = tester.ensureSemantics();
        final rig = await _Rig.open(tester);

        final data = tester.getSemantics(rig.row('cut')).getSemanticsData();
        expect(data.label, 'Cut');
        expect(data.hint, 'Ctrl+X');
        handle.dispose();
      },
    );

    testWidgets('a disabled row is spoken as disabled', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(tester);

      expect(
        tester
            .getSemantics(rig.row('redo'))
            .getSemanticsData()
            .flagsCollection
            .isEnabled,
        Tristate.isFalse,
      );
      handle.dispose();
    });
  });

  group('choosing', () {
    testWidgets('a click on a row runs it and closes the menu', (tester) async {
      final rig = await _Rig.open(tester);
      await rig.glideTo(rig.center('copy'));

      await rig.mouse.down(rig.center('copy'));
      await rig.mouse.up();
      await rig.settle();

      expect(rig.chosen, ['copy']);
      expect(rig.handle.isOpen, isFalse);
      expect(find.byKey(const PointerMenuPanelKey(0)), findsNothing);
    });

    testWidgets('a click on a disabled row does nothing and keeps the menu', (
      tester,
    ) async {
      final rig = await _Rig.open(tester);
      await rig.glideTo(rig.center('redo'));

      await rig.mouse.down(rig.center('redo'));
      await rig.mouse.up();
      await rig.settle();

      expect(rig.chosen, isEmpty);
      expect(rig.handle.isOpen, isTrue);
    });

    testWidgets('a click on a row that opens a submenu opens it', (
      tester,
    ) async {
      final rig = await _Rig.open(tester);
      await rig.glideTo(rig.center('format'));

      expect(rig.row('bold'), findsOneWidget);
    });

    testWidgets('a row of a submenu closes the whole menu', (tester) async {
      final rig = await _Rig.open(tester);
      await rig.glideTo(rig.center('format'));
      await rig.glideTo(rig.center('bold'));
      await rig.glideTo(rig.center('underline'));

      await rig.mouse.down(rig.center('underline'));
      await rig.mouse.up();
      await rig.settle();

      expect(rig.chosen, ['underline']);
      expect(rig.handle.isOpen, isFalse);
    });

    testWidgets('the press that opened the menu cannot choose the row under '
        'it', (tester) async {
      // A menu taller than the screen is pushed in so that a row lies under
      // the pointer that opened it.
      final rig = await _Rig.open(
        tester,
        at: const Offset(50, 50),
        screen: const Size(200, 200),
      );
      await rig.mouse.moveTo(const Offset(51, 51));
      await tester.pump();
      await rig.mouse.down(const Offset(51, 51));
      await rig.mouse.up();
      await rig.settle();

      expect(rig.chosen, isEmpty);
      expect(rig.handle.isOpen, isTrue);
    });

    testWidgets('rows react once the pointer has moved six times', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(
        tester,
        at: const Offset(50, 30),
        screen: const Size(200, 200),
      );

      for (var i = 1; i <= 6; i++) {
        await rig.mouse.moveTo(Offset(50 + i * 0.1, 30));
        await tester.pump();
      }
      expect(rig.selected('undo'), isFalse);

      await rig.mouse.moveTo(const Offset(50.7, 30));
      await tester.pump();
      // The seventh motion opens the guard for the row under the pointer.
      expect(rig.selected('undo'), isTrue);
      handle.dispose();
    });
  });

  group('dismissal', () {
    testWidgets('a press outside closes the menu and goes no further', (
      tester,
    ) async {
      final rig = await _Rig.open(tester);

      await rig.mouse.down(const Offset(600, 500));
      await rig.mouse.up();
      await rig.settle();

      expect(rig.handle.isOpen, isFalse);
      expect(_Rig.underlyingTaps, 0);
    });

    testWidgets('Escape closes the menu', (tester) async {
      final rig = await _Rig.open(tester);

      await rig.key(LogicalKeyboardKey.escape);
      await rig.settle();

      expect(rig.handle.isOpen, isFalse);
      expect(rig.chosen, isEmpty);
    });

    testWidgets('the handle closes it', (tester) async {
      final rig = await _Rig.open(tester);

      rig.handle.close();
      await rig.settle();

      expect(rig.handle.isOpen, isFalse);
      await rig.handle.closed;
    });

    testWidgets('a menu with no row to choose never opens', (tester) async {
      final rig = await _Rig.open(
        tester,
        entries: const [PointerMenuItem(id: 'a', label: 'A')],
      );

      expect(rig.handle.isOpen, isFalse);
    });

    testWidgets('onClosed is told when the menu is gone', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.expand())),
      );
      final handle = PointerMenu.show(
        tester.element(find.byType(Scaffold)),
        globalPosition: const Offset(10, 10),
        entries: [PointerMenuItem(id: 'a', label: 'A', onSelected: () {})],
        tokens: PointerMenuTokens.referenceDay,
        motion: const ChromeMotionData(speed: ChromeMotionSpeed.instant),
        onClosed: () => closed++,
      );
      await tester.pump();
      handle.close();
      await tester.pumpAndSettle();

      expect(closed, 1);
    });
  });

  group('keyboard', () {
    testWidgets('Down from nothing selects the first row that can be chosen', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(tester);

      await rig.key(LogicalKeyboardKey.arrowDown);

      expect(rig.selected('undo'), isTrue);
      handle.dispose();
    });

    testWidgets('Down skips the disabled row and the separator', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(tester);

      await rig.key(LogicalKeyboardKey.arrowDown);
      await rig.key(LogicalKeyboardKey.arrowDown);

      expect(rig.selected('cut'), isTrue);
      handle.dispose();
    });

    testWidgets(
      'Up from nothing selects the last row; Down wraps to the first',
      (tester) async {
        final handle = tester.ensureSemantics();
        final rig = await _Rig.open(tester);

        await rig.key(LogicalKeyboardKey.arrowUp);
        expect(rig.selected('all'), isTrue);

        await rig.key(LogicalKeyboardKey.arrowDown);
        expect(rig.selected('undo'), isTrue);
        handle.dispose();
      },
    );

    testWidgets('Enter runs the selected row', (tester) async {
      final rig = await _Rig.open(tester);

      await rig.key(LogicalKeyboardKey.arrowDown);
      await rig.key(LogicalKeyboardKey.enter);
      await rig.settle();

      expect(rig.chosen, ['undo']);
      expect(rig.handle.isOpen, isFalse);
    });

    testWidgets('Space runs the selected row', (tester) async {
      final rig = await _Rig.open(tester);

      await rig.key(LogicalKeyboardKey.arrowUp);
      await rig.key(LogicalKeyboardKey.space);
      await rig.settle();

      expect(rig.chosen, ['all']);
    });

    testWidgets('Enter with nothing selected does nothing', (tester) async {
      final rig = await _Rig.open(tester);

      await rig.key(LogicalKeyboardKey.enter);

      expect(rig.chosen, isEmpty);
      expect(rig.handle.isOpen, isTrue);
    });

    testWidgets('Right opens the submenu and selects its first live row', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(tester);
      await rig.key(LogicalKeyboardKey.arrowUp);
      await rig.key(LogicalKeyboardKey.arrowUp);
      expect(rig.selected('format'), isTrue);

      await rig.key(LogicalKeyboardKey.arrowRight);

      expect(rig.row('bold'), findsOneWidget);
      expect(rig.selected('bold'), isTrue);
      handle.dispose();
    });

    testWidgets('Left closes the submenu and keeps the menu', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(tester);
      await rig.key(LogicalKeyboardKey.arrowUp);
      await rig.key(LogicalKeyboardKey.arrowUp);
      await rig.key(LogicalKeyboardKey.arrowRight);

      await rig.key(LogicalKeyboardKey.arrowLeft);

      expect(rig.row('bold'), findsNothing);
      expect(rig.selected('format'), isTrue);
      expect(rig.handle.isOpen, isTrue);
      handle.dispose();
    });

    testWidgets('Escape closes the submenu first, then the menu', (
      tester,
    ) async {
      final rig = await _Rig.open(tester);
      await rig.key(LogicalKeyboardKey.arrowUp);
      await rig.key(LogicalKeyboardKey.arrowUp);
      await rig.key(LogicalKeyboardKey.arrowRight);

      await rig.key(LogicalKeyboardKey.escape);
      expect(rig.row('bold'), findsNothing);
      expect(rig.handle.isOpen, isTrue);

      await rig.key(LogicalKeyboardKey.escape);
      await rig.settle();
      expect(rig.handle.isOpen, isFalse);
    });

    testWidgets('Enter on a submenu row opens it', (tester) async {
      final rig = await _Rig.open(tester);
      await rig.key(LogicalKeyboardKey.arrowUp);
      await rig.key(LogicalKeyboardKey.arrowUp);

      await rig.key(LogicalKeyboardKey.enter);

      expect(rig.row('bold'), findsOneWidget);
      expect(rig.handle.isOpen, isTrue);
    });

    testWidgets(
      'Down moves inside the open submenu, skipping its disabled row',
      (tester) async {
        final handle = tester.ensureSemantics();
        final rig = await _Rig.open(tester);
        await rig.key(LogicalKeyboardKey.arrowUp);
        await rig.key(LogicalKeyboardKey.arrowUp);
        await rig.key(LogicalKeyboardKey.arrowRight);

        await rig.key(LogicalKeyboardKey.arrowDown);

        expect(rig.selected('underline'), isTrue);
        handle.dispose();
      },
    );

    testWidgets('in right-to-left Left opens and Right closes', (tester) async {
      final rig = await _Rig.open(
        tester,
        at: const Offset(400, 100),
        direction: TextDirection.rtl,
      );
      await rig.key(LogicalKeyboardKey.arrowUp);
      await rig.key(LogicalKeyboardKey.arrowUp);

      await rig.key(LogicalKeyboardKey.arrowLeft);
      expect(rig.row('bold'), findsOneWidget);

      await rig.key(LogicalKeyboardKey.arrowRight);
      expect(rig.row('bold'), findsNothing);
    });

    testWidgets('other keys go nowhere: a parent field hears nothing', (
      tester,
    ) async {
      var heard = 0;
      final field = FocusNode(
        onKeyEvent: (node, event) {
          heard++;
          return KeyEventResult.ignored;
        },
      );
      addTearDown(field.dispose);
      final rig = await _Rig.open(
        tester,
        focusParent: field,
        above: Focus(focusNode: field, child: const SizedBox.shrink()),
      );

      await rig.key(LogicalKeyboardKey.keyA);
      await rig.key(LogicalKeyboardKey.tab);

      expect(heard, 0);
    });
  });

  group('submenus', () {
    testWidgets('hover opens the submenu at once, touching the parent', (
      tester,
    ) async {
      final rig = await _Rig.open(tester);

      await rig.glideTo(rig.center('format'));

      final parent = rig.panel();
      final sub = rig.panel(1);
      expect(sub.left, parent.right);
    });

    testWidgets(
      'the submenu\'s first row is level with the row that opened it',
      (tester) async {
        final rig = await _Rig.open(tester);

        await rig.glideTo(rig.center('format'));

        expect(
          tester.getRect(rig.row('bold')).top,
          tester.getRect(rig.row('format')).top,
        );
      },
    );

    testWidgets('moving to another row of the parent closes the submenu', (
      tester,
    ) async {
      final rig = await _Rig.open(tester);
      await rig.glideTo(rig.center('format'));

      await rig.mouse.moveTo(rig.center('cut'));
      await tester.pump();

      expect(rig.row('bold'), findsNothing);
    });

    testWidgets('rows crossed on the way to the submenu do not take the '
        'highlight, until the pointer pauses', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = await _Rig.open(tester);
      await rig.glideTo(rig.center('format'));
      final start = rig.center('format');
      // Down and to the right, toward the submenu's near edge, across 'all'.
      final subTop = rig.panel(1).topLeft;
      final across = Offset(rig.panel().right - 4, rig.center('all').dy);
      expect(across.dy, greaterThan(start.dy));

      await rig.mouse.moveTo(Offset.lerp(start, across, 0.5)!);
      await rig.mouse.moveTo(across);
      await tester.pump();

      expect(rig.selected('all'), isFalse);
      expect(rig.row('bold'), findsOneWidget);
      expect(subTop, rig.panel(1).topLeft);

      await tester.pump(PointerMenuTiming.aimHold);
      await tester.pump(const Duration(milliseconds: 1));
      await rig.mouse.moveTo(across + const Offset(-1, 0));
      await tester.pump();

      expect(rig.selected('all'), isTrue);
      expect(rig.row('bold'), findsNothing);
      handle.dispose();
    });
  });

  group('motion', () {
    testWidgets('the panel is invisible at the start and opaque at the end', (
      tester,
    ) async {
      final rig = await _Rig.open(tester, motion: ChromeMotionData.standard);
      double opacity() => tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byKey(const PointerMenuPanelKey(0)),
              matching: find.byType(Opacity),
            ),
          )
          .first
          .opacity;

      expect(opacity(), lessThan(0.5));
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), 1);
      await rig.settle();
      expect(opacity(), 1);
    });

    testWidgets('closing fades out over 150 ms and then removes the menu', (
      tester,
    ) async {
      final rig = await _Rig.open(tester, motion: ChromeMotionData.standard);
      await rig.settle();

      rig.handle.close();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(rig.handle.isOpen, isTrue);
      final fading = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byKey(const PointerMenuPanelKey(0)),
              matching: find.byType(Opacity),
            ),
          )
          .first
          .opacity;
      expect(fading, closeTo(0.5, 0.05));

      await tester.pump(const Duration(milliseconds: 80));
      expect(rig.handle.isOpen, isFalse);
    });

    testWidgets('under an instant speed the menu is there and gone at once', (
      tester,
    ) async {
      final rig = await _Rig.open(tester);

      expect(rig.handle.isOpen, isTrue);
      rig.handle.close();
      await tester.pump();
      await tester.pump();

      expect(rig.handle.isOpen, isFalse);
    });
  });

  group('focus', () {
    testWidgets(
      'the menu is a child of the field\'s focus node and gives focus '
      'back as it closes',
      (tester) async {
        final field = FocusNode();
        addTearDown(field.dispose);
        final rig = await _Rig.open(
          tester,
          focusParent: field,
          returnFocusTo: field,
          above: Focus(focusNode: field, child: const SizedBox.shrink()),
        );

        await rig.key(LogicalKeyboardKey.arrowDown);
        expect(field.hasFocus, isTrue);
        expect(field.hasPrimaryFocus, isFalse);

        await rig.key(LogicalKeyboardKey.escape);
        await rig.settle();
        expect(field.hasPrimaryFocus, isTrue);
      },
    );

    testWidgets('focus is back on the field before the chosen row runs', (
      tester,
    ) async {
      final field = FocusNode();
      addTearDown(field.dispose);
      bool? primaryWhenRun;
      final rig = await _Rig.open(
        tester,
        focusParent: field,
        returnFocusTo: field,
        focused: field,
        above: Focus(focusNode: field, child: const SizedBox.shrink()),
        entries: [
          PointerMenuItem(
            id: 'a',
            label: 'A',
            onSelected: () => primaryWhenRun = field.hasPrimaryFocus,
          ),
        ],
      );

      await rig.key(LogicalKeyboardKey.arrowDown);
      await rig.key(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(primaryWhenRun, isTrue);
    });
  });
}
