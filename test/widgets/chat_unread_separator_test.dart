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

Widget _unread(BuildContext context) =>
    const SizedBox(height: 32, child: Text('unread'));

Widget _unreadAlt(BuildContext context) =>
    const SizedBox(height: 32, child: Text('unread-alt'));

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ValueListenable<int?>? unreadBoundary,
  WidgetBuilder? unreadSeparatorBuilder = _unread,
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
          selectionController: selection,
          onIdleMessageTap: onIdleMessageTap,
          onSecondaryMessageTap: onSecondaryMessageTap,
          messageBuilder: _message,
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
      expect(_top(tester, 'msg-16'), dateTop + 24 + 32);
      expect(_rowOf(tester, 'unread').size.height, 24 + 32 + 60);
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
      expect(_top(tester, 'msg-18'), sepTop + 32);
      expect(_rowOf(tester, 'unread').size.height, 32 + 60);
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
      expect(_top(tester, 'msg-16'), _top(tester, 'unread') + 32);
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

    testWidgets('swapping the boundary listenable moves the separator', (
      tester,
    ) async {
      final source = _loaded(64);
      final controller = _controllerAt(14);
      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: controller,
          unreadBoundary: _boundary(18),
        ),
      );
      await tester.pump();
      expect(_top(tester, 'msg-18'), _top(tester, 'unread') + 32);

      await tester.pumpWidget(
        _harness(
          dataSource: source,
          controller: controller,
          unreadBoundary: _boundary(19),
        ),
      );
      await tester.pump();

      expect(find.text('unread'), findsOneWidget);
      expect(_top(tester, 'msg-19'), _top(tester, 'unread') + 32);
      expect(
        _top(tester, 'msg-18'),
        tester.getBottomLeft(find.text('msg-17')).dy,
      );
    });
  });
}
