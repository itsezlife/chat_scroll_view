import 'dart:async';
import 'dart:math' as math;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// Messages per calendar day: ids 0, 8, 16, … start a day.
const int _perDay = 8;

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026, 1, 1 + i ~/ _perDay, 9, i % _perDay),
  updatedAt: DateTime(2026, 1, 1 + i ~/ _perDay, 9, i % _perDay),
  content: 'content $i',
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(int count) {
    upsertMessages(<IChatMessage>[for (var i = 0; i < count; i++) _msg(i)]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// Boundaries 0–9; only id 5 is loaded, the rest render as shimmer.
class _SparseSource extends ChatDataSource {
  _SparseSource() {
    upsertMessage(_msg(5));
    seedBoundaries(oldestKnownId: 0, newestKnownId: 9);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// Boundaries 0–9; fetches never resolve, so rows stay shimmer until the
/// test upserts them.
class _LateSource extends ChatDataSource {
  _LateSource() {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: 9,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) => Completer<List<IChatMessage>>().future;
}

/// Ids `0..count-1` known, all loaded but [unloaded]; fetches never resolve,
/// so an unloaded row stays shimmer and a reach flag stays as seeded.
class _PartialSource extends ChatDataSource {
  _PartialSource(
    int count, {
    Set<int> unloaded = const <int>{},
    bool reachedNewest = true,
  }) {
    upsertMessages(<IChatMessage>[
      for (var i = 0; i < count; i++)
        if (!unloaded.contains(i)) _msg(i),
    ]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: reachedNewest,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) => Completer<List<IChatMessage>>().future;
}

/// Every fetch fails, so every chunk ends in error.
class _FailingSource extends ChatDataSource {
  _FailingSource(this.count) {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  final int count;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw StateError('fetch failed');
  }
}

// Stable builders: a closure per pump would clear the skip cache on every
// rebuild and hide what a builder swap does.

Widget _message(
  BuildContext context,
  int id,
  IChatMessage? message,
  ChatMessageStatus status,
  MessageRunLayout runLayout,
) => SizedBox(
  height: 60,
  child: Text(switch (message) {
    null => 'shimmer-$id',
    _ => 'msg-$id',
  }),
);

Widget _date(BuildContext context, Object bucket, DateTime date) =>
    SizedBox(height: 24, child: Text('sep-${date.month}-${date.day}'));

const _separatorHeight = 32.0;

Widget _unread(BuildContext context) =>
    const SizedBox(height: _separatorHeight, child: Text('unread'));

Widget _unreadAlt(BuildContext context) =>
    const SizedBox(height: _separatorHeight, child: Text('unread-alt'));

/// Separator builder that counts the frames that paint a separator.
final class _PaintedSeparator {
  int paints = 0;

  Widget call(BuildContext context) => CustomPaint(
    painter: _CountingPainter(this),
    child: _unread(context),
  );
}

final class _CountingPainter extends CustomPainter {
  _CountingPainter(this.counter);

  final _PaintedSeparator counter;

  @override
  void paint(Canvas canvas, Size size) => counter.paints++;

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

/// Message builder that counts how often each id is built.
final class _BuildCounter {
  final Map<int, int> builds = <int, int>{};

  Widget call(
    BuildContext context,
    int id,
    IChatMessage? message,
    ChatMessageStatus status,
    MessageRunLayout runLayout,
  ) {
    builds.update(id, (count) => count + 1, ifAbsent: () => 1);
    return _message(context, id, message, status, runLayout);
  }
}

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ValueListenable<int?>? unreadBoundary,
  WidgetBuilder? unreadSeparatorBuilder = _unread,
  ChatMessageBuilder messageBuilder = _message,
  ValueListenable<double>? bottomPadding,
  ValueListenable<double>? topPadding,
  bool separators = true,
  ChatSelectionController? selection,
  ChatMessageMenuRequestCallback? onIdleMessageTap,
  ChatMessageMenuRequestCallback? onSecondaryMessageTap,
}) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.iOS),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          bottomPadding: bottomPadding,
          topPadding: topPadding,
          selectionController: selection,
          onIdleMessageTap: onIdleMessageTap,
          onSecondaryMessageTap: onSecondaryMessageTap,
          messageBuilder: messageBuilder,
          dateSeparatorBuilder: separators ? _date : null,
          unreadBoundary: unreadBoundary,
          unreadSeparatorBuilder: unreadSeparatorBuilder,
        ),
      ),
    ),
  ),
);

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

/// The row chrome render object of the row that paints [text].
RenderChatRowChrome _rowOf(WidgetTester tester, String text) =>
    tester.renderObject<RenderChatRowChrome>(
      find.ancestor(of: find.text(text), matching: find.byType(ChatRowChrome)),
    );

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

_LoadedSource _loaded(int count) {
  final source = _LoadedSource(count);
  addTearDown(source.dispose);
  return source;
}

ValueNotifier<int?> _boundary(int? id) {
  final notifier = ValueNotifier<int?>(id);
  addTearDown(notifier.dispose);
  return notifier;
}

ChatScrollController _controllerAt(int id) {
  final controller = ChatScrollController()..jumpTo(id);
  addTearDown(controller.dispose);
  return controller;
}

// Transition TRACE (see the unread-bar worked guide): the extent follows the
// 250 ms list-item move curve; the exit fade runs 120 ms and the enter fade
// and scale 250 ms, both along the exact sine ease-in-out.
const _frame = Duration(milliseconds: 10);

double _sine(double t) => (1 - math.cos(math.pi * t.clamp(0.0, 1.0))) / 2;

double _move(int ms) => kChatMessageChangeCurve.transform((ms / 250).clamp(0, 1));

double _exitOpacity(int ms) => 1 - _sine(ms / 120);

double _enterFade(int ms) => _sine(ms / 250);

Matcher _near(double value) => moreOrLessEquals(value, epsilon: 1e-6);

/// Width of the separator's box on screen, row chrome scale included.
double _separatorWidth(WidgetTester tester) => tester
    .getRect(
      find
          .ancestor(of: find.text('unread'), matching: find.byType(SizedBox))
          .first,
    )
    .width;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('Unread separator order', () {
    testWidgets('a boundary row that starts a day stacks date, separator, '
        'then body', (tester) async {
      // jumpTo(14): the floating header shows day 2, so 'sep-1-3' is the
      // inline date of row 16 only.
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(14),
          unreadBoundary: _boundary(16),
        ),
      );
      await tester.pump();

      final dateTop = _top(tester, 'sep-1-3');
      expect(_top(tester, 'unread'), dateTop + 24);
      expect(_top(tester, 'msg-16'), dateTop + 24 + _separatorHeight);
      expect(_rowOf(tester, 'unread').size.height, 24 + _separatorHeight + 60);
      expect(find.text('unread'), findsOneWidget);
    });

    testWidgets('a boundary row inside a day stacks separator, then body', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(14),
          unreadBoundary: _boundary(18),
        ),
      );
      await tester.pump();

      final sepTop = _top(tester, 'unread');
      expect(sepTop, tester.getBottomLeft(find.text('msg-17')).dy);
      expect(_top(tester, 'msg-18'), sepTop + _separatorHeight);
      expect(_rowOf(tester, 'unread').size.height, _separatorHeight + 60);
    });

    testWidgets('with day grouping off the separator still paints', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(14),
          unreadBoundary: _boundary(16),
          separators: false,
        ),
      );
      await tester.pump();

      expect(find.textContaining('sep-'), findsNothing);
      expect(_top(tester, 'msg-16'), _top(tester, 'unread') + _separatorHeight);
    });
  });

  group('Unread separator gates', () {
    testWidgets('a null boundary paints no separator', (tester) async {
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(14),
          unreadBoundary: _boundary(null),
        ),
      );
      await tester.pump();

      expect(find.text('unread'), findsNothing);
    });

    testWidgets('a boundary without a separator builder paints nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(14),
          unreadBoundary: _boundary(16),
          unreadSeparatorBuilder: null,
        ),
      );
      await tester.pump();

      expect(find.text('unread'), findsNothing);
      expect(
        _top(tester, 'msg-16'),
        _top(tester, 'sep-1-3') + 24,
        reason: 'the boundary row keeps date-only chrome',
      );
    });

    testWidgets('a shimmer row gets no separator', (tester) async {
      final source = _SparseSource();
      addTearDown(source.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: _controllerAt(5),
          unreadBoundary: _boundary(3),
        ),
      );
      await tester.pump();

      expect(find.text('shimmer-3'), findsOneWidget);
      expect(find.text('unread'), findsNothing);
    });

    testWidgets('an errored row gets no separator', (tester) async {
      final source = _FailingSource(64);
      addTearDown(source.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: _controllerAt(63),
          unreadBoundary: _boundary(62),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(find.text('shimmer-62'), findsOneWidget);
      expect(find.text('unread'), findsNothing);
    });

    testWidgets('a boundary on an absent id paints nothing', (tester) async {
      final source = _loaded(24);
      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: _controllerAt(23),
          unreadBoundary: _boundary(20),
        ),
      );
      await tester.pump();
      expect(find.text('unread'), findsOneWidget);

      source.removeMessages(<int>[20]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('msg-20'), findsNothing);
      expect(find.text('unread'), findsNothing);
    });
  });

  group('Unread separator presentation', () {
    testWidgets('the separator stays opaque while the date above it fades', (
      tester,
    ) async {
      // jumpTo(16): row 16 sits at the top, its date inside the floating
      // header zone.
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(16),
          unreadBoundary: _boundary(16),
        ),
      );
      await tester.pump();

      expect(_render(tester).debugDividerOpacity(16), lessThan(0.5));
      final row = _rowOf(tester, 'unread');
      expect(row.chromeCount, 2);
      expect(row.debugChromeEffect(0).opacity, lessThan(0.5));
      expect(row.debugChromeEffect(1), ChatRowChromeEffect.visible);
    });
  });

  group('Unread separator input', () {
    testWidgets('tap, secondary tap, and long press on the separator reach '
        'no message; on the body they do', (tester) async {
      final idle = <ChatMessageMenuRequest>[];
      final secondary = <ChatMessageMenuRequest>[];
      final selection = ChatSelectionController();
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(24),
          controller: _controllerAt(23),
          unreadBoundary: _boundary(20),
          selection: selection,
          onIdleMessageTap: idle.add,
          onSecondaryMessageTap: secondary.add,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('unread'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('unread'),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('unread'));
      await tester.pumpAndSettle();

      expect(idle, isEmpty);
      expect(secondary, isEmpty);
      expect(selection.isSelectionMode, isFalse);

      await tester.tap(find.text('msg-20'));
      await tester.pumpAndSettle();
      expect(idle.map((r) => r.messageId), <int>[20]);
    });

    testWidgets('the separator sits outside selection chrome and the '
        'secondary-tap scope', (tester) async {
      final selection = ChatSelectionController();
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(24),
          controller: _controllerAt(23),
          unreadBoundary: _boundary(20),
          selection: selection,
          onSecondaryMessageTap: (_) {},
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('msg-20'));
      await tester.pumpAndSettle();
      expect(selection.isSelected(20), isTrue);

      Finder above(String text, Type type) =>
          find.ancestor(of: find.text(text), matching: find.byType(type));
      expect(above('msg-20', SelectableMessage), findsOneWidget);
      expect(above('unread', SelectableMessage), findsNothing);
      expect(above('msg-20', ChatSecondaryMessageTapScope), findsOneWidget);
      expect(above('unread', ChatSecondaryMessageTapScope), findsNothing);
    });
  });

  group('Unread separator inputs swap', () {
    testWidgets('swapping the separator builder rebuilds built rows', (
      tester,
    ) async {
      final source = _loaded(64);
      final controller = _controllerAt(14);
      final boundary = _boundary(18);
      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: controller,
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();
      expect(find.text('unread'), findsOneWidget);

      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: controller,
          unreadBoundary: boundary,
          unreadSeparatorBuilder: _unreadAlt,
        ),
      );
      await tester.pump();

      expect(find.text('unread'), findsNothing);
      expect(find.text('unread-alt'), findsOneWidget);
    });

    testWidgets('swapping the boundary listenable moves the separator and '
        'follows only the new listenable', (tester) async {
      final source = _loaded(64);
      final controller = _controllerAt(14);
      final first = _boundary(18);
      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: controller,
          unreadBoundary: first,
        ),
      );
      await tester.pump();
      expect(_top(tester, 'msg-18'), _top(tester, 'unread') + _separatorHeight);

      final second = _boundary(19);
      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: controller,
          unreadBoundary: second,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('unread'), findsOneWidget);
      expect(_top(tester, 'msg-19'), _top(tester, 'unread') + _separatorHeight);
      expect(
        _top(tester, 'msg-18'),
        tester.getBottomLeft(find.text('msg-17')).dy,
      );

      first.value = 17;
      await tester.pumpAndSettle();
      expect(_top(tester, 'msg-19'), _top(tester, 'unread') + _separatorHeight);

      second.value = 21;
      await tester.pumpAndSettle();
      expect(find.text('unread'), findsOneWidget);
      expect(_top(tester, 'msg-21'), _top(tester, 'unread') + _separatorHeight);
    });
  });

  group('Live unread boundary', () {
    testWidgets('moving the boundary rebuilds only the old and the new '
        'boundary row', (tester) async {
      final counter = _BuildCounter();
      final boundary = _boundary(18);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(14),
          unreadBoundary: boundary,
          messageBuilder: counter.call,
        ),
      );
      await tester.pump();
      final belowTop = _top(tester, 'msg-22');
      counter.builds.clear();

      boundary.value = 20;
      await tester.pump();
      expect(counter.builds, <int, int>{20: 1});
      expect(find.text('unread'), findsNWidgets(2));

      await tester.pumpAndSettle();

      expect(counter.builds, <int, int>{18: 1, 20: 1});
      expect(find.text('unread'), findsOneWidget);
      expect(_top(tester, 'msg-20'), _top(tester, 'unread') + _separatorHeight);
      expect(
        _top(tester, 'msg-18'),
        tester.getBottomLeft(find.text('msg-17')).dy,
      );
      expect(_top(tester, 'msg-22'), _near(belowTop));
    });

    for (final (from, to, verb) in <(int?, int?, String)>[
      (null, 18, 'setting'),
      (18, null, 'clearing'),
    ]) {
      testWidgets('$verb the boundary off the tail keeps the bodies at and '
          'below the row in place', (tester) async {
        final boundary = _boundary(from);
        await tester.pumpWidget(
          _harness(
            dataSource: _loaded(64),
            controller: _controllerAt(14),
            unreadBoundary: boundary,
          ),
        );
        await tester.pump();
        final bodies = <int, double>{
          for (final id in <int>[18, 19, 22]) id: _top(tester, 'msg-$id'),
        };
        final aboveTop = _top(tester, 'msg-15');

        boundary.value = to;
        await tester.pumpAndSettle();

        for (final MapEntry(key: id, value: top) in bodies.entries) {
          expect(_top(tester, 'msg-$id'), _near(top), reason: 'msg-$id');
        }
        expect(
          _top(tester, 'msg-15'),
          _near(aboveTop + (to == null ? _separatorHeight : -_separatorHeight)),
          reason: 'the rows above the boundary row absorb the change',
        );
        expect(find.text('unread'), to == null ? findsNothing : findsOneWidget);
      });

      testWidgets('$verb the boundary at the tail keeps the newest row '
          'pinned above the bottom inset', (tester) async {
        final inset = ValueNotifier<double>(40);
        addTearDown(inset.dispose);
        final boundary = _boundary(from == null ? null : 60);
        // Rows 56–63 are shorter than the band: the clamp pins the newest
        // row to the band bottom and leaves the anchor above the boundary.
        final controller = _controllerAt(56);
        await tester.pumpWidget(
          _harness(
            dataSource: _loaded(64),
            controller: controller,
            unreadBoundary: boundary,
            bottomPadding: inset,
          ),
        );
        await tester.pump();
        final bandBottom =
            tester.getTopLeft(find.byType(ChatScrollView)).dy + 600 - 40;
        expect(tester.getBottomLeft(find.text('msg-63')).dy, bandBottom);
        final bodyTop = _top(tester, 'msg-61');

        boundary.value = to == null ? null : 60;
        await tester.pumpAndSettle();

        expect(tester.getBottomLeft(find.text('msg-63')).dy, _near(bandBottom));
        expect(_top(tester, 'msg-61'), _near(bodyTop));
        expect(controller.isAtTail.value, isTrue);
        expect(find.text('unread'), to == null ? findsNothing : findsOneWidget);
      });
    }

    testWidgets('a boundary row that loads later gets the separator on that '
        'build', (tester) async {
      final source = _LateSource();
      addTearDown(source.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: _controllerAt(5),
          unreadBoundary: _boundary(3),
        ),
      );
      await tester.pump();
      expect(find.text('shimmer-3'), findsOneWidget);
      expect(find.text('unread'), findsNothing);

      source.upsertMessage(_msg(3));
      await tester.pump();

      expect(find.text('unread'), findsOneWidget);
      expect(_top(tester, 'msg-3'), _top(tester, 'unread') + _separatorHeight);
    });

    testWidgets('moving the boundary onto an absent id paints nothing', (
      tester,
    ) async {
      final source = _loaded(24);
      final boundary = _boundary(22);
      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: _controllerAt(23),
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();
      source.removeMessages(<int>[20]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      boundary.value = 20;
      await tester.pumpAndSettle();

      expect(find.text('msg-20'), findsNothing);
      expect(find.text('unread'), findsNothing);
    });
  });

  // jumpTo(14) leaves row 18 on screen, inside day 3 (16 starts it), so the
  // separator is chrome item 0 of row 18.
  group('Unread separator transition', () {
    testWidgets('clearing fades the separator over 120 ms while its slot '
        'collapses over 250 ms and the rows below hold still', (tester) async {
      final boundary = _boundary(18);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(14),
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();
      final bodies = <int, double>{
        for (final id in <int>[18, 19, 22]) id: _top(tester, 'msg-$id'),
      };
      final aboveTop = _top(tester, 'msg-15');
      final row = _rowOf(tester, 'unread');

      boundary.value = null;
      await tester.pump();
      for (var ms = 0; ms < 250; ms += 10) {
        if (ms > 0) await tester.pump(_frame);
        expect(find.text('unread'), findsOneWidget, reason: '$ms ms');
        expect(
          row.debugChromeEffect(0).opacity,
          _near(_exitOpacity(ms)),
          reason: 'opacity at $ms ms',
        );
        expect(row.debugChromeEffect(0).hitTestable, isFalse);
        for (final MapEntry(key: id, value: top) in bodies.entries) {
          expect(_top(tester, 'msg-$id'), _near(top), reason: 'msg-$id $ms ms');
        }
        expect(
          _top(tester, 'msg-15'),
          _near(aboveTop + _separatorHeight * _move(ms)),
          reason: 'slot at $ms ms',
        );
      }
      await tester.pump(_frame);

      expect(find.text('unread'), findsNothing);
      for (final MapEntry(key: id, value: top) in bodies.entries) {
        expect(_top(tester, 'msg-$id'), _near(top), reason: 'msg-$id');
      }
      expect(_top(tester, 'msg-15'), _near(aboveTop + _separatorHeight));
    });

    testWidgets('setting grows the slot while the separator fades in and '
        'scales from 0.9 over 250 ms', (tester) async {
      final boundary = _boundary(null);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(14),
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();
      final bodies = <int, double>{
        for (final id in <int>[18, 19, 22]) id: _top(tester, 'msg-$id'),
      };
      final aboveTop = _top(tester, 'msg-15');

      boundary.value = 18;
      await tester.pump();
      final row = _rowOf(tester, 'unread');
      for (var ms = 0; ms < 250; ms += 10) {
        if (ms > 0) await tester.pump(_frame);
        expect(
          row.debugChromeEffect(0).opacity,
          _near(_enterFade(ms)),
          reason: 'opacity at $ms ms',
        );
        expect(
          _separatorWidth(tester),
          _near(400 * (0.9 + 0.1 * _enterFade(ms))),
          reason: 'scale at $ms ms',
        );
        for (final MapEntry(key: id, value: top) in bodies.entries) {
          expect(_top(tester, 'msg-$id'), _near(top), reason: 'msg-$id $ms ms');
        }
        expect(
          _top(tester, 'msg-15'),
          _near(aboveTop - _separatorHeight * _move(ms)),
          reason: 'slot at $ms ms',
        );
      }
      await tester.pump(_frame);

      expect(row.debugChromeEffect(0), ChatRowChromeEffect.visible);
      expect(_separatorWidth(tester), 400);
      expect(_top(tester, 'msg-18'), _near(_top(tester, 'unread') + 32));
      expect(_top(tester, 'msg-15'), _near(aboveTop - _separatorHeight));
    });

    for (final (from, to, verb) in <(int?, int?, String)>[
      (null, 60, 'setting'),
      (60, null, 'clearing'),
    ]) {
      testWidgets('$verb the boundary at the tail keeps the newest row pinned '
          'on every frame', (tester) async {
        final inset = ValueNotifier<double>(40);
        addTearDown(inset.dispose);
        final boundary = _boundary(from);
        await tester.pumpWidget(
          _harness(
            dataSource: _loaded(64),
            controller: _controllerAt(56),
            unreadBoundary: boundary,
            bottomPadding: inset,
          ),
        );
        await tester.pump();
        final bandBottom =
            tester.getTopLeft(find.byType(ChatScrollView)).dy + 600 - 40;
        final bodyTop = _top(tester, 'msg-60');

        boundary.value = to;
        await tester.pump();
        for (var ms = 0; ms <= 250; ms += 10) {
          if (ms > 0) await tester.pump(_frame);
          expect(
            tester.getBottomLeft(find.text('msg-63')).dy,
            _near(bandBottom),
            reason: 'newest at $ms ms',
          );
          expect(_top(tester, 'msg-60'), _near(bodyTop), reason: '$ms ms');
        }
        expect(find.text('unread'), to == null ? findsNothing : findsOneWidget);
      });
    }

    testWidgets('a boundary change mid-exit retargets from the current '
        'frame without a jump or a rebuild', (tester) async {
      final counter = _BuildCounter();
      final boundary = _boundary(18);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(14),
          unreadBoundary: boundary,
          messageBuilder: counter.call,
        ),
      );
      await tester.pump();
      final aboveTop = _top(tester, 'msg-15');
      final row = _rowOf(tester, 'unread');

      boundary.value = null;
      await tester.pump();
      for (var ms = 10; ms <= 60; ms += 10) {
        await tester.pump(_frame);
      }
      final opacity = row.debugChromeEffect(0).opacity;
      final top = _top(tester, 'msg-15');
      expect(opacity, _near(0.5));
      counter.builds.clear();

      boundary.value = 18;
      await tester.pump();
      expect(row.debugChromeEffect(0).opacity, _near(opacity));
      expect(_top(tester, 'msg-15'), _near(top));
      for (var ms = 10; ms <= 250; ms += 10) {
        await tester.pump(_frame);
        expect(
          row.debugChromeEffect(0).opacity,
          _near(opacity + (1 - opacity) * _enterFade(ms)),
          reason: 'opacity at $ms ms',
        );
        expect(
          _top(tester, 'msg-15'),
          _near(aboveTop + (top - aboveTop) * (1 - _move(ms))),
          reason: 'slot at $ms ms',
        );
      }

      expect(row.debugChromeEffect(0), ChatRowChromeEffect.visible);
      expect(_top(tester, 'msg-15'), _near(aboveTop));
      expect(counter.builds, isEmpty);
    });

    testWidgets('moving the boundary runs both legs at once and keeps the '
        'rows below both still', (tester) async {
      final boundary = _boundary(18);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(14),
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();
      final belowTop = _top(tester, 'msg-22');

      boundary.value = 20;
      await tester.pump();
      for (var ms = 0; ms < 250; ms += 10) {
        if (ms > 0) await tester.pump(_frame);
        expect(find.text('unread'), findsNWidgets(2), reason: '$ms ms');
        expect(_top(tester, 'msg-22'), _near(belowTop), reason: '$ms ms');
      }
      await tester.pump(_frame);

      expect(find.text('unread'), findsOneWidget);
      expect(_top(tester, 'msg-20'), _top(tester, 'unread') + 32);
      expect(_top(tester, 'msg-22'), _near(belowTop));
    });

    testWidgets('with tickers muted a change lands in one frame, and muting '
        'settles a running transition', (tester) async {
      final source = _loaded(64);
      final controller = _controllerAt(14);
      final boundary = _boundary(18);
      Widget app({required bool ticking}) => TickerMode(
        enabled: ticking,
        child: _harness(
          dataSource: source,
          controller: controller,
          unreadBoundary: boundary,
        ),
      );
      await tester.pumpWidget(app(ticking: true));
      await tester.pump();

      boundary.value = 20;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('unread'), findsNWidgets(2));

      await tester.pumpWidget(app(ticking: false));
      expect(find.text('unread'), findsOneWidget);
      expect(_top(tester, 'msg-20'), _top(tester, 'unread') + 32);

      boundary.value = null;
      await tester.pump();
      expect(find.text('unread'), findsNothing);
    });

    testWidgets('deleting the boundary row mid-exit drops it with its '
        'separator', (tester) async {
      final source = _loaded(24);
      final boundary = _boundary(20);
      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: _controllerAt(23),
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();

      boundary.value = null;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      source.removeMessages(<int>[20]);
      await tester.pumpAndSettle();

      expect(find.text('msg-20'), findsNothing);
      expect(find.text('unread'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an animated scroll keeps the origin while a separator '
        'transitions', (tester) async {
      final controller = _controllerAt(14);
      final boundary = _boundary(18);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: controller,
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();

      unawaited(controller.animateTo(42, highlight: false));
      boundary.value = null;
      await tester.pumpAndSettle();

      expect(
        _top(tester, 'msg-42'),
        _near(tester.getTopLeft(find.byType(ChatScrollView)).dy),
      );
      expect(find.text('unread'), findsNothing);
    });
  });

  group('Alignment hold', () {
    double bandTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(ChatScrollView)).dy;

    testWidgets('adding the separator to the held target keeps the separator '
        'at the band top and the body below it', (tester) async {
      final boundary = _boundary(null);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(20),
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();
      expect(_top(tester, 'msg-20'), bandTop(tester));

      boundary.value = 20;
      await tester.pump();
      for (var ms = 0; ms < 250; ms += 10) {
        if (ms > 0) await tester.pump(_frame);
        expect(
          _top(tester, 'msg-20'),
          _near(bandTop(tester) + _separatorHeight * _move(ms)),
          reason: 'the row top holds the band top at $ms ms',
        );
      }
      await tester.pump(_frame);

      expect(_top(tester, 'unread'), _near(bandTop(tester)));
      expect(_top(tester, 'msg-20'), _near(bandTop(tester) + _separatorHeight));
    });

    testWidgets('clearing the separator from the held target keeps the body '
        'at the band top', (tester) async {
      final boundary = _boundary(20);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(20),
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();
      expect(_top(tester, 'unread'), bandTop(tester));

      boundary.value = null;
      await tester.pumpAndSettle();

      expect(find.text('unread'), findsNothing);
      expect(_top(tester, 'msg-20'), _near(bandTop(tester)));
    });

    testWidgets('a top inset change keeps the held target, row chrome '
        'included, at the band top', (tester) async {
      final inset = ValueNotifier<double>(0);
      addTearDown(inset.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(20),
          unreadBoundary: _boundary(20),
          topPadding: inset,
        ),
      );
      await tester.pump();
      expect(_top(tester, 'unread'), bandTop(tester));

      inset.value = 56;
      await tester.pump();

      expect(_top(tester, 'unread'), bandTop(tester) + 56);
      expect(_top(tester, 'msg-20'), bandTop(tester) + 56 + _separatorHeight);
    });

    testWidgets('moving the separator off the held target keeps the body at '
        'the band top', (tester) async {
      final boundary = _boundary(20);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(20),
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();

      boundary.value = 22;
      await tester.pumpAndSettle();

      expect(_top(tester, 'msg-20'), _near(bandTop(tester)));
      expect(_top(tester, 'unread'), _top(tester, 'msg-22') - _separatorHeight);
    });

    testWidgets('a top inset change in the same pass as a separator on '
        'another row keeps the held target at the band top on that pass; '
        'the transition then holds the rows below', (tester) async {
      final boundary = _boundary(null);
      final inset = ValueNotifier<double>(0);
      addTearDown(inset.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(20),
          unreadBoundary: boundary,
          topPadding: inset,
        ),
      );
      await tester.pump();

      boundary.value = 22;
      inset.value = 56;
      await tester.pump();
      expect(_top(tester, 'msg-20'), bandTop(tester) + 56);
      final belowTop = _top(tester, 'msg-23');
      await tester.pumpAndSettle();

      expect(_top(tester, 'msg-23'), _near(belowTop));
      expect(
        _top(tester, 'msg-20'),
        _near(bandTop(tester) + 56 - _separatorHeight),
      );
      expect(_top(tester, 'unread'), _top(tester, 'msg-22') - _separatorHeight);
    });

    testWidgets('after a drag the former target falls back to the row chrome '
        'hold', (tester) async {
      final boundary = _boundary(null);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: _controllerAt(20),
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 50));
      await tester.pumpAndSettle();
      final bodyTop = _top(tester, 'msg-20');

      boundary.value = 20;
      await tester.pumpAndSettle();

      expect(_top(tester, 'msg-20'), _near(bodyTop));
      expect(_top(tester, 'unread'), _near(bodyTop - _separatorHeight));
    });
  });

  // 600 px viewport, 60 px rows, newest 63; fraction 0.5 allows 300 px from
  // the target's body top to the newest row's bottom.
  group('Tail-or-target open', () {
    double bandTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(ChatScrollView)).dy;
    double bandBottom(WidgetTester tester) => bandTop(tester) + 600;

    List<TailOrTargetOutcome> outcomesOf(ChatScrollController controller) {
      final outcomes = <TailOrTargetOutcome>[];
      controller.addTailOrTargetListener(outcomes.add);
      return outcomes;
    }

    ChatScrollController tailOrTargetAt(int id) {
      final controller = ChatScrollController()
        ..jumpTo(id, tailFitFraction: 0.5);
      addTearDown(controller.dispose);
      return controller;
    }

    testWidgets('a span within the fraction opens pinned at the tail', (
      tester,
    ) async {
      final controller = tailOrTargetAt(60);
      final outcomes = outcomesOf(controller);
      await tester.pumpWidget(
        _harness(dataSource: _loaded(64), controller: controller),
      );

      expect(outcomes, <TailOrTargetOutcome>[TailOrTargetOutcome.tail]);
      expect(tester.getBottomLeft(find.text('msg-63')).dy, bandBottom(tester));
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('a span beyond the fraction places the target as a plain '
        'jump does', (tester) async {
      final separator = _PaintedSeparator();
      final controller = tailOrTargetAt(58);
      final outcomes = outcomesOf(controller);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: controller,
          unreadBoundary: _boundary(58),
          unreadSeparatorBuilder: separator.call,
        ),
      );

      expect(outcomes, <TailOrTargetOutcome>[TailOrTargetOutcome.target]);
      expect(separator.paints, 1);
      // Rows 58–63 and the separator are shorter than the band: the
      // boundary clamp still pins the newest row, as after `jumpTo(58)`.
      expect(tester.getBottomLeft(find.text('msg-63')).dy, bandBottom(tester));
      expect(
        _top(tester, 'unread'),
        bandBottom(tester) - 6 * 60 - _separatorHeight,
      );
    });

    testWidgets("the fit measure excludes the target row's row chrome", (
      tester,
    ) async {
      // Rows 59–63 span exactly 300 px; the separator would add 32.
      final controller = tailOrTargetAt(59);
      final outcomes = outcomesOf(controller);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: controller,
          unreadBoundary: _boundary(59),
        ),
      );

      expect(outcomes, <TailOrTargetOutcome>[TailOrTargetOutcome.tail]);
      expect(tester.getBottomLeft(find.text('msg-63')).dy, bandBottom(tester));
    });

    testWidgets('an unloaded newest message reports target', (tester) async {
      final source = _PartialSource(64, unloaded: <int>{63});
      addTearDown(source.dispose);
      final controller = tailOrTargetAt(60);
      final outcomes = outcomesOf(controller);
      await tester.pumpWidget(
        _harness(dataSource: source, controller: controller),
      );

      expect(outcomes, <TailOrTargetOutcome>[TailOrTargetOutcome.target]);
    });

    testWidgets('a newest message not yet reached aligns the target', (
      tester,
    ) async {
      final source = _PartialSource(64, reachedNewest: false);
      addTearDown(source.dispose);
      final controller = tailOrTargetAt(60);
      final outcomes = outcomesOf(controller);
      await tester.pumpWidget(
        _harness(dataSource: source, controller: controller),
      );

      expect(outcomes, <TailOrTargetOutcome>[TailOrTargetOutcome.target]);
      expect(_top(tester, 'msg-60'), bandTop(tester));
    });

    testWidgets('a newest message beyond the built rows aligns the target', (
      tester,
    ) async {
      final controller = tailOrTargetAt(20);
      final outcomes = outcomesOf(controller);
      await tester.pumpWidget(
        _harness(dataSource: _loaded(64), controller: controller),
      );

      expect(outcomes, <TailOrTargetOutcome>[TailOrTargetOutcome.target]);
      expect(_top(tester, 'msg-20'), bandTop(tester));
    });

    testWidgets('a boundary clear made by the listener lands in the same '
        'layout: no frame paints the separator', (tester) async {
      final separator = _PaintedSeparator();
      final boundary = _boundary(60);
      final controller = tailOrTargetAt(60)
        ..addTailOrTargetListener((outcome) {
          if (outcome == TailOrTargetOutcome.tail) boundary.value = null;
        });
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: controller,
          unreadBoundary: boundary,
          unreadSeparatorBuilder: separator.call,
        ),
      );

      expect(separator.paints, 0);
      expect(find.text('unread'), findsNothing);
      expect(tester.getBottomLeft(find.text('msg-63')).dy, bandBottom(tester));
      expect(_top(tester, 'msg-60'), bandBottom(tester) - 4 * 60);
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(separator.paints, 0, reason: 'frame $frame');
      }
    });

    testWidgets('a boundary set by the listener on a target outcome is '
        'seated with the target in the same layout', (tester) async {
      final boundary = _boundary(null);
      final controller = ChatScrollController()
        ..jumpTo(20, alignment: 1, tailFitFraction: 0.5)
        ..addTailOrTargetListener((outcome) {
          if (outcome == TailOrTargetOutcome.target) boundary.value = 20;
        });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _harness(
          dataSource: _loaded(64),
          controller: controller,
          unreadBoundary: boundary,
        ),
      );

      expect(tester.getBottomLeft(find.text('msg-20')).dy, bandBottom(tester));
      expect(_top(tester, 'unread'), bandBottom(tester) - 60 - _separatorHeight);
    });

    testWidgets('a target that is not loaded resolves on the layout that '
        'loads it', (tester) async {
      final source = _LateSource();
      addTearDown(source.dispose);
      final controller = tailOrTargetAt(7);
      final outcomes = outcomesOf(controller);
      await tester.pumpWidget(
        _harness(dataSource: source, controller: controller),
      );
      await tester.pump();
      expect(outcomes, isEmpty);

      source.upsertMessages(<IChatMessage>[for (var i = 0; i < 10; i++) _msg(i)]);
      await tester.pump();

      expect(outcomes, <TailOrTargetOutcome>[TailOrTargetOutcome.tail]);
      expect(tester.getBottomLeft(find.text('msg-9')).dy, bandBottom(tester));
    });

    testWidgets('a jump released before its target loads reports nothing', (
      tester,
    ) async {
      final source = _LateSource();
      addTearDown(source.dispose);
      final controller = tailOrTargetAt(7);
      final outcomes = outcomesOf(controller);
      await tester.pumpWidget(
        _harness(dataSource: source, controller: controller),
      );
      controller.scrollBy(10);
      await tester.pump();

      source.upsertMessages(<IChatMessage>[for (var i = 0; i < 10; i++) _msg(i)]);
      await tester.pump();

      expect(outcomes, isEmpty);
    });

    testWidgets('a jump replaced before its first layout reports nothing', (
      tester,
    ) async {
      final controller = tailOrTargetAt(60)..jumpTo(20);
      final outcomes = outcomesOf(controller);
      await tester.pumpWidget(
        _harness(dataSource: _loaded(64), controller: controller),
      );

      expect(outcomes, isEmpty);
      expect(_top(tester, 'msg-20'), bandTop(tester));
    });

    testWidgets('a listener that navigates fails an assert', (tester) async {
      final controller = tailOrTargetAt(60);
      controller.addTailOrTargetListener((_) => controller.scrollBy(10));
      await tester.pumpWidget(
        _harness(dataSource: _loaded(64), controller: controller),
      );

      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('a jump issued after mount resolves on its next layout, '
        'once', (tester) async {
      final controller = _controllerAt(20);
      final outcomes = outcomesOf(controller);
      await tester.pumpWidget(
        _harness(dataSource: _loaded(64), controller: controller),
      );

      controller.jumpTo(61, tailFitFraction: 0.5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(outcomes, <TailOrTargetOutcome>[TailOrTargetOutcome.tail]);
      expect(tester.getBottomLeft(find.text('msg-63')).dy, bandBottom(tester));
    });

    testWidgets('outcome listeners dedup and dispatch over a snapshot', (
      tester,
    ) async {
      final controller = tailOrTargetAt(60);
      final calls = <String>[];
      void first(TailOrTargetOutcome _) {
        calls.add('first');
        controller.removeTailOrTargetListener(first);
      }

      void second(TailOrTargetOutcome _) => calls.add('second');
      void removed(TailOrTargetOutcome _) => calls.add('removed');
      controller
        ..addTailOrTargetListener(first)
        ..addTailOrTargetListener(second)
        ..addTailOrTargetListener(second)
        ..addTailOrTargetListener(removed)
        ..removeTailOrTargetListener(removed);
      await tester.pumpWidget(
        _harness(dataSource: _loaded(64), controller: controller),
      );

      expect(calls, <String>['first', 'second']);
    });
  });
}
