import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swipe_pager/swipe_pager.dart';

void main() {
  late SwipePagerController controller;
  late Map<int, int> created;
  late Map<int, int> disposed;
  late List<int> changes;
  late List<double> positions;

  setUp(() {
    controller = SwipePagerController();
    created = {};
    disposed = {};
    changes = [];
    positions = [];
    controller.addPositionListener(positions.add);
  });

  tearDown(() => controller.dispose());

  Future<void> pump(
    WidgetTester tester, {
    int pages = 4,
    SwipePagerKeepAlive keepAlive = const SwipePagerKeepAlive.all(),
    TextDirection direction = TextDirection.ltr,
    bool disableAnimations = false,
    bool focusable = false,
    FocusNode? focusNode,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: direction,
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            devicePixelRatio: 3,
            disableAnimations: disableAnimations,
          ),
          child: SwipePager(
            controller: controller,
            pageCount: pages,
            keepAlive: keepAlive,
            focusable: focusable,
            focusNode: focusNode,
            onPageChanged: changes.add,
            pageBuilder: (context, index) =>
                _Probe(index: index, created: created, disposed: disposed),
          ),
        ),
      ),
    );
  }

  group('animateTo', () {
    testWidgets('slides over 540 ms and lands on the page', (tester) async {
      await pump(tester);
      final done = controller.animateTo(1);
      expect(controller.page, 1);
      expect(changes, [1]);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 270));
      expect(controller.position, inExclusiveRange(0.5, 1));
      expect(controller.isSettling, isTrue);

      // An animation ends on the first frame past its duration.
      await tester.pump(const Duration(milliseconds: 271));
      expect(controller.position, 1);
      expect(controller.isSettling, isFalse);
      await done;
    });

    testWidgets('brings a far page in next to the current one', (tester) async {
      await pump(tester);
      unawaited(controller.animateTo(3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('page 3'), findsOneWidget);
      expect(find.text('page 0'), findsOneWidget);
      expect(created.keys, isNot(contains(1)));
      expect(created.keys, isNot(contains(2)));
      // The incoming page is right of the current one.
      expect(
        tester.getTopLeft(find.text('page 3')).dx,
        greaterThan(tester.getTopLeft(find.text('page 0')).dx),
      );
      expect(controller.position, inExclusiveRange(0, 3));
      await tester.pumpAndSettle();
      expect(controller.position, 3);
      expect(find.text('page 0'), findsNothing);
    });

    testWidgets('jumps when animations are disabled', (tester) async {
      await pump(tester, disableAnimations: true);
      await controller.animateTo(2);
      expect(controller.position, 2);
      expect(controller.isSettling, isFalse);
    });

    testWidgets('a swipe during a slide is not taken', (tester) async {
      await pump(tester);
      unawaited(controller.animateTo(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.dragFrom(const Offset(400, 300), const Offset(-300, 0));
      expect(controller.isDragging, isFalse);
      await tester.pumpAndSettle();
      expect(controller.page, 1);
    });
  });

  group('jumpTo', () {
    testWidgets('lands at once and notifies once', (tester) async {
      await pump(tester);
      controller.jumpTo(2);
      await tester.pump();

      expect(controller.position, 2);
      expect(changes, [2]);
      expect(positions, [2]);
      expect(find.text('page 2'), findsOneWidget);
      expect(find.text('page 0'), findsNothing);
    });

    testWidgets('to the same page notifies nobody', (tester) async {
      await pump(tester);
      controller.jumpTo(0);
      expect(changes, isEmpty);
      expect(positions, isEmpty);
    });

    testWidgets('clamps to the pages there are', (tester) async {
      await pump(tester);
      controller.jumpTo(9);
      expect(controller.page, 3);
    });
  });

  group('keep-alive', () {
    Future<void> visit(WidgetTester tester, List<int> pages) async {
      for (final page in pages) {
        controller.jumpTo(page);
        await tester.pump();
      }
    }

    testWidgets('all: every page keeps its state', (tester) async {
      await pump(tester);
      await visit(tester, [1, 2, 3, 0]);

      expect(disposed, isEmpty);
      expect(created, {0: 1, 1: 1, 2: 1, 3: 1});
    });

    testWidgets('a kept page is offstage with its tickers off', (tester) async {
      await pump(tester);
      await visit(tester, [1]);

      final kept = find.text('page 0', skipOffstage: false);
      expect(kept, findsOneWidget);
      expect(find.text('page 0'), findsNothing);
      expect(TickerMode.valuesOf(tester.element(kept)).enabled, isFalse);
      expect(
        TickerMode.valuesOf(tester.element(find.text('page 1'))).enabled,
        isTrue,
      );
    });

    testWidgets('none: a page left is disposed and built anew', (tester) async {
      await pump(tester, keepAlive: const SwipePagerKeepAlive.none());
      await visit(tester, [1, 0]);

      expect(disposed, {0: 1, 1: 1});
      expect(created, {0: 2, 1: 1});
    });

    testWidgets('recent: the pages last settled on stay', (tester) async {
      await pump(tester, keepAlive: const SwipePagerKeepAlive.recent(2));
      await visit(tester, [1, 2]);

      expect(disposed, {0: 1});
      await visit(tester, [1]);
      expect(disposed, {0: 1});
      await visit(tester, [3]);
      expect(disposed, {0: 1, 2: 1});
    });

    testWidgets('both pages stay built through a swipe', (tester) async {
      await pump(tester, keepAlive: const SwipePagerKeepAlive.none());
      final gesture = await tester.startGesture(const Offset(400, 300));
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(-4, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('page 0'), findsOneWidget);
      expect(find.text('page 1'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(controller.page, 0);
      expect(disposed, {1: 1});
      expect(created, {0: 1, 1: 1});
    });
  });

  group('keyboard', () {
    testWidgets('the arrows page while the pager holds the focus', (
      tester,
    ) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pump(tester, focusable: true, focusNode: focus);
      focus.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(controller.page, 0);
    });

    testWidgets('mirror right to left', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pump(
        tester,
        focusable: true,
        focusNode: focus,
        direction: TextDirection.rtl,
      );
      focus.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(controller.page, 1);
    });

    testWidgets('do nothing when a page child holds the focus', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pump(tester, focusable: true, focusNode: focus);
      Focus.of(tester.element(find.text('page 0'))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.page, 0);
    });

    testWidgets('pages off screen are out of focus traversal', (tester) async {
      await pump(tester);
      final kept = find.text('page 0', skipOffstage: false);
      await tester.pump();
      controller.jumpTo(1);
      await tester.pump();

      expect(Focus.of(tester.element(kept)).canRequestFocus, isFalse);
      expect(
        Focus.of(tester.element(find.text('page 1'))).canRequestFocus,
        isTrue,
      );
    });
  });

  group('semantics', () {
    testWidgets('scroll left and right page, mirrored right to left', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      final node = tester.getSemantics(find.byType(SwipePager));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.scrollRight),
        isFalse,
      );

      tester.semantics.scrollLeft();
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(
        tester
            .getSemantics(find.byType(SwipePager))
            .getSemanticsData()
            .hasAction(SemanticsAction.scrollRight),
        isTrue,
      );

      await pump(tester, direction: TextDirection.rtl);
      tester.semantics.scrollRight();
      await tester.pumpAndSettle();
      expect(controller.page, 2);
      semantics.dispose();
    });

    testWidgets('only the page on screen is in the tree', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      controller.jumpTo(1);
      await tester.pump();

      expect(find.bySemanticsLabel('page 1'), findsOneWidget);
      expect(find.bySemanticsLabel('page 0'), findsNothing);
      semantics.dispose();
    });
  });

  group('the controller', () {
    testWidgets('notifies a listener added twice once', (tester) async {
      await pump(tester);
      final pages = <int>[];
      controller
        ..addPageListener(pages.add)
        ..addPageListener(pages.add);
      controller.jumpTo(1);
      expect(pages, [1]);
    });

    testWidgets('detached, animateTo jumps', (tester) async {
      final detached = SwipePagerController(initialPage: 2);
      addTearDown(detached.dispose);
      await detached.animateTo(0);
      expect(detached.page, 0);
    });

    testWidgets('starts the pager on its initial page', (tester) async {
      controller.dispose();
      controller = SwipePagerController(initialPage: 2);
      await pump(tester);
      expect(find.text('page 2'), findsOneWidget);
      expect(created.keys, [2]);
    });

    testWidgets('after dispose, moves are silent', (tester) async {
      final spent = SwipePagerController()..dispose();
      spent.jumpTo(3);
      expect(spent.page, 0);
      expect(spent.isDisposed, isTrue);
    });
  });
}

/// A page that counts its states.
class _Probe extends StatefulWidget {
  const _Probe({
    required this.index,
    required this.created,
    required this.disposed,
  });

  final int index;
  final Map<int, int> created;
  final Map<int, int> disposed;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.created.update(widget.index, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    widget.disposed.update(widget.index, (n) => n + 1, ifAbsent: () => 1);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(child: Center(child: Text('page ${widget.index}')));
}
