import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_sender_run_layout.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../chat_message.dart';

IChatMessage _msg(int id, {String sender = 'bot', DateTime? when}) =>
    UserChatMessage(
      id: id,
      sender: sender,
      createdAt: when ?? DateTime(2026, 5, 29, 10, id),
      updatedAt: when ?? DateTime(2026, 5, 29, 10, id),
      content: 'body-$id',
    );

class _LoadedSource extends ChatDataSource {
  _LoadedSource(Iterable<IChatMessage> messages) {
    upsertMessages(messages);
    if (messages.isEmpty) return;
    final ids = messages.map((m) => m.id).toList()..sort();
    seedBoundaries(
      oldestKnownId: ids.first,
      newestKnownId: ids.last,
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

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required ChatMessageBuilder messageBuilder,
  ChatGroupSeparatorBuilder? dateSeparatorBuilder,
  Object Function(IChatMessage message)? groupBy,
  ChatSenderRunLayout senderRunLayout = DefaultChatSenderRunLayout.instance,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          dateSeparatorBuilder: dateSeparatorBuilder,
          groupBy: groupBy,
          senderRunLayout: senderRunLayout,
          messageBuilder: messageBuilder,
        ),
      ),
    ),
  ),
);

/// Last-in-run chrome marker for tests.
Widget _chromeBuilder(
  BuildContext context,
  int id,
  IChatMessage? message,
  ChatMessageStatus status,
  MessageRunLayout runLayout,
) {
  if (message == null) return const SizedBox(height: 40);
  return SizedBox(
    height: 40,
    child: Text(
      runLayout.isLastInSenderRun ? 'chrome-$id' : 'plain-$id',
      key: ValueKey<String>('row-$id'),
    ),
  );
}

/// First-in-run chrome marker — proves Layer A is policy-agnostic.
Widget _firstChromeBuilder(
  BuildContext context,
  int id,
  IChatMessage? message,
  ChatMessageStatus status,
  MessageRunLayout runLayout,
) {
  if (message == null) return const SizedBox(height: 40);
  return SizedBox(
    height: 40,
    child: Text(
      runLayout.isFirstInSenderRun ? 'first-$id' : 'mid-$id',
      key: ValueKey<String>('row-$id'),
    ),
  );
}

Future<void> _pumpLoaded(
  WidgetTester tester,
  ChatDataSource ds,
  ChatMessageBuilder builder, {
  ChatGroupSeparatorBuilder? separator,
}) async {
  final controller = ChatScrollController()..jumpTo(ds.newestKnownId!);
  await tester.pumpWidget(
    _harness(
      dataSource: ds,
      controller: controller,
      messageBuilder: builder,
      dateSeparatorBuilder: separator,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('sender run chrome', () {
    testWidgets('delete first of two regains last-in-run chrome', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2)]);

      await _pumpLoaded(tester, ds, _chromeBuilder);
      expect(find.text('plain-1'), findsOneWidget);
      expect(find.text('chrome-2'), findsOneWidget);

      ds.removeMessages([1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('plain-1'), findsNothing);
      expect(find.text('chrome-2'), findsOneWidget);
    });

    testWidgets('three-message run shows chrome only on last id', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);

      await _pumpLoaded(tester, ds, _chromeBuilder);
      expect(find.text('plain-1'), findsOneWidget);
      expect(find.text('plain-2'), findsOneWidget);
      expect(find.text('chrome-3'), findsOneWidget);
    });

    testWidgets('same sender across two day buckets — chrome on each last', (
      tester,
    ) async {
      final ds = _LoadedSource([
        _msg(1, when: DateTime(2026, 5, 29, 10)),
        _msg(2, when: DateTime(2026, 5, 30, 10)),
      ]);

      await _pumpLoaded(
        tester,
        ds,
        _chromeBuilder,
        separator: (context, bucket, date) => const SizedBox(height: 28),
      );

      expect(find.text('chrome-1'), findsOneWidget);
      expect(find.text('chrome-2'), findsOneWidget);
    });

    testWidgets('insert extends run — chrome moves to new last', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1)]);

      await _pumpLoaded(tester, ds, _chromeBuilder);
      expect(find.text('chrome-1'), findsOneWidget);

      ds.insertMessage(_msg(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('plain-1'), findsOneWidget);
      expect(find.text('chrome-2'), findsOneWidget);
    });

    testWidgets('delete last of three promotes chrome to new last', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);

      await _pumpLoaded(tester, ds, _chromeBuilder);
      ds.removeMessages([3]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('chrome-2'), findsOneWidget);
      expect(find.text('chrome-3'), findsNothing);
    });

    testWidgets('first-in-run harness rebuilds after delete', (tester) async {
      final ds = _LoadedSource([_msg(1), _msg(2)]);

      await _pumpLoaded(tester, ds, _firstChromeBuilder);
      expect(find.text('first-1'), findsOneWidget);
      expect(find.text('mid-2'), findsOneWidget);

      ds.removeMessages([1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('first-2'), findsOneWidget);
    });

    testWidgets('demo incoming bubble shows avatar only on last in run', (
      tester,
    ) async {
      final ds = _LoadedSource([
        _msg(1, sender: 'skia-gold'),
        _msg(2, sender: 'skia-gold'),
      ]);
      final controller = ChatScrollController()..jumpTo(2);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: ds,
                  controller: controller,
                  messageBuilder: (context, id, message, status, runLayout) {
                    if (message == null) return const SizedBox(height: 40);
                    // Proxy for last-in-run chrome (avatar / sender label).
                    return SizedBox(
                      height: 40,
                      child: runLayout.isLastInSenderRun
                          ? Text(message.sender)
                          : const SizedBox.shrink(),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('skia-gold'), findsOneWidget);

      ds.removeMessages([1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('skia-gold'), findsOneWidget);
    });

    testWidgets('delete middle of three keeps chrome on last', (tester) async {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);

      await _pumpLoaded(tester, ds, _chromeBuilder);
      ds.removeMessages([2]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('plain-1'), findsOneWidget);
      expect(find.text('chrome-3'), findsOneWidget);
    });

    testWidgets('custom groupBy splits same-sender runs', (tester) async {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);
      final controller = ChatScrollController()..jumpTo(3);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          messageBuilder: _chromeBuilder,
          dateSeparatorBuilder: (context, bucket, date) =>
              const SizedBox(height: 8),
          groupBy: (message) => message.id <= 1 ? 'first' : 'rest',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('chrome-1'), findsOneWidget);
      expect(find.text('plain-2'), findsOneWidget);
      expect(find.text('chrome-3'), findsOneWidget);
    });

    testWidgets('maxClusterGap splits same-sender run by createdAt', (
      tester,
    ) async {
      final t0 = DateTime(2026, 5, 29, 10);
      final ds = _LoadedSource([
        _msg(1, when: t0),
        _msg(2, when: t0.add(const Duration(minutes: 2))),
        _msg(3, when: t0.add(const Duration(minutes: 12))),
      ]);
      final controller = ChatScrollController()..jumpTo(3);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          messageBuilder: _chromeBuilder,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1–2 within 5 min → one run (chrome on 2); 3 starts a new run.
      expect(find.text('plain-1'), findsOneWidget);
      expect(find.text('chrome-2'), findsOneWidget);
      expect(find.text('chrome-3'), findsOneWidget);
    });

    testWidgets('custom senderRunLayout replaces clustering policy', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);
      final controller = ChatScrollController()..jumpTo(3);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          messageBuilder: _chromeBuilder,
          senderRunLayout: const _AlwaysAloneRunLayout(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('chrome-1'), findsOneWidget);
      expect(find.text('chrome-2'), findsOneWidget);
      expect(find.text('chrome-3'), findsOneWidget);
    });

    testWidgets('neighbor sender update rebuilds run layout', (tester) async {
      final ds = _LoadedSource([_msg(1, sender: 'a'), _msg(2, sender: 'a')]);

      await _pumpLoaded(tester, ds, _chromeBuilder);
      expect(find.text('plain-1'), findsOneWidget);
      expect(find.text('chrome-2'), findsOneWidget);

      ds.updateMessage(_msg(1, sender: 'b'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('chrome-1'), findsOneWidget);
      expect(find.text('chrome-2'), findsOneWidget);
    });

    testWidgets(
      'extras change with same first/last reinflates only flipped ids',
      (tester) async {
        final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);
        final controller = ChatScrollController()..jumpTo(3);
        final builds = <int, int>{};

        Widget builder(
          BuildContext context,
          int id,
          IChatMessage? message,
          ChatMessageStatus status,
          MessageRunLayout runLayout,
        ) {
          builds[id] = (builds[id] ?? 0) + 1;
          if (message == null) return const SizedBox(height: 40);
          final tag = runLayout.extras == true ? 'extra' : 'plain';
          return SizedBox(
            height: 40,
            child: Text('$tag-$id', key: ValueKey<String>('row-$id')),
          );
        }

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            messageBuilder: builder,
            senderRunLayout: const _ExtrasRunLayout(flaggedIds: {}),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('plain-1'), findsOneWidget);
        expect(find.text('plain-2'), findsOneWidget);
        expect(find.text('plain-3'), findsOneWidget);
        final afterFirst = Map<int, int>.from(builds);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            messageBuilder: builder,
            senderRunLayout: const _ExtrasRunLayout(flaggedIds: {2}),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('plain-1'), findsOneWidget);
        expect(find.text('extra-2'), findsOneWidget);
        expect(find.text('plain-3'), findsOneWidget);
        expect(builds[2], greaterThan(afterFirst[2]!));
        expect(builds[1], afterFirst[1]);
        expect(builds[3], afterFirst[3]);
      },
    );

    testWidgets('same extras keeps skip-rebuild hit', (tester) async {
      final ds = _LoadedSource([_msg(1), _msg(2)]);
      final controller = ChatScrollController()..jumpTo(2);
      final builds = <int, int>{};

      Widget builder(
        BuildContext context,
        int id,
        IChatMessage? message,
        ChatMessageStatus status,
        MessageRunLayout runLayout,
      ) {
        builds[id] = (builds[id] ?? 0) + 1;
        if (message == null) return const SizedBox(height: 40);
        return SizedBox(
          height: 40,
          child: Text('row-$id', key: ValueKey<String>('row-$id')),
        );
      }

      const policy = _ExtrasRunLayout(flaggedIds: {1, 2});

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          messageBuilder: builder,
          senderRunLayout: policy,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final afterFirst = Map<int, int>.from(builds);

      // Equal policy instance → no markNeedsLayout; identical messages → skip.
      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          messageBuilder: builder,
          senderRunLayout: policy,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(builds[1], afterFirst[1]);
      expect(builds[2], afterFirst[2]);
    });

    testWidgets('Listenable policy notify reinflates only flipped extras', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);
      final controller = ChatScrollController()..jumpTo(3);
      final policy = _LiveExtrasRunLayout();
      final builds = <int, int>{};

      Widget builder(
        BuildContext context,
        int id,
        IChatMessage? message,
        ChatMessageStatus status,
        MessageRunLayout runLayout,
      ) {
        builds[id] = (builds[id] ?? 0) + 1;
        if (message == null) return const SizedBox(height: 40);
        final tag = runLayout.extras == true ? 'extra' : 'plain';
        return SizedBox(
          height: 40,
          child: Text('$tag-$id', key: ValueKey<String>('row-$id')),
        );
      }

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          messageBuilder: builder,
          senderRunLayout: policy,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('plain-1'), findsOneWidget);
      expect(find.text('plain-2'), findsOneWidget);
      expect(find.text('plain-3'), findsOneWidget);
      final afterFirst = Map<int, int>.from(builds);

      // Same policy instance; live input bump notifies Listenable.
      policy.flagId(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('plain-1'), findsOneWidget);
      expect(find.text('extra-2'), findsOneWidget);
      expect(find.text('plain-3'), findsOneWidget);
      expect(builds[2], greaterThan(afterFirst[2]!));
      expect(builds[1], afterFirst[1]);
      expect(builds[3], afterFirst[3]);
    });
  });
}

class _AlwaysAloneRunLayout implements ChatSenderRunLayout {
  const _AlwaysAloneRunLayout();

  @override
  MessageRunLayout resolve({
    required ChatDataSource dataSource,
    required int messageId,
    Object? Function(IChatMessage)? groupBy,
  }) =>
      const MessageRunLayout(isFirstInSenderRun: true, isLastInSenderRun: true);
}

/// Wraps default clustering and tags [flaggedIds] via [MessageRunLayout.extras].
@immutable
class _ExtrasRunLayout implements ChatSenderRunLayout {
  const _ExtrasRunLayout({required this.flaggedIds});

  final Set<int> flaggedIds;

  @override
  MessageRunLayout resolve({
    required ChatDataSource dataSource,
    required int messageId,
    Object? Function(IChatMessage)? groupBy,
  }) {
    final base = DefaultChatSenderRunLayout.instance.resolve(
      dataSource: dataSource,
      messageId: messageId,
      groupBy: groupBy,
    );
    return MessageRunLayout(
      isFirstInSenderRun: base.isFirstInSenderRun,
      isLastInSenderRun: base.isLastInSenderRun,
      extras: flaggedIds.contains(messageId),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _ExtrasRunLayout && setEquals(other.flaggedIds, flaggedIds);

  @override
  int get hashCode => Object.hashAll(flaggedIds);
}

/// Live extras policy: one instance, [ChangeNotifier] bump without widget swap.
final class _LiveExtrasRunLayout extends ChangeNotifier
    implements ChatSenderRunLayout {
  final Set<int> _flaggedIds = <int>{};

  void flagId(int id) {
    if (!_flaggedIds.add(id)) return;
    notifyListeners();
  }

  @override
  MessageRunLayout resolve({
    required ChatDataSource dataSource,
    required int messageId,
    Object? Function(IChatMessage)? groupBy,
  }) {
    final base = DefaultChatSenderRunLayout.instance.resolve(
      dataSource: dataSource,
      messageId: messageId,
      groupBy: groupBy,
    );
    return MessageRunLayout(
      isFirstInSenderRun: base.isFirstInSenderRun,
      isLastInSenderRun: base.isLastInSenderRun,
      extras: _flaggedIds.contains(messageId),
    );
  }
}
