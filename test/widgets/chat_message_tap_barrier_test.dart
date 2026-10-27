import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

/// [ChatMessageTapBarrier] against the real [ChatScrollView]: the viewport's
/// selection pointer listens above the gesture arena, so only the viewport's
/// own seam can keep a press on row chrome from being a message press.
IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $id',
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: messages.length - 1,
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

class _Rig {
  _Rig(this.selection, this.idle, this.secondary);

  final ChatSelectionController selection;
  final List<int> idle;
  final List<int> secondary;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder barrierOf(int id) => find.descendant(
    of: find.byKey(ValueKey('row-$id')),
    matching: find.byKey(const ValueKey('barrier')),
  );

  /// Three 120-high rows, each with a body line and an 80 x 30 barrier
  /// under it at the start edge; the rest of the row is plain message.
  Future<_Rig> mount(
    WidgetTester tester, {
    required ChatSelectionPolicy policy,
    bool barrierEnabled = true,
    bool markdown = false,
  }) async {
    final selection = ChatSelectionController(policy: policy);
    final controller = ChatScrollController()..jumpTo(2);
    final dataSource = _LoadedSource([for (var i = 0; i < 3; i++) _msg(i)]);
    addTearDown(selection.dispose);
    addTearDown(controller.dispose);
    addTearDown(dataSource.dispose);
    if (markdown) {
      for (var i = 0; i < 3; i++) {
        selection.putBody(i, Markdown.fromString('Hello selectable world'));
      }
    }
    final idle = <int>[];
    final secondary = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatScrollView(
              dataSource: dataSource,
              controller: controller,
              selectionController: selection,
              onIdleMessageTap: (request) => idle.add(request.messageId),
              onSecondaryMessageTap: (request) =>
                  secondary.add(request.messageId),
              messageBuilder: (context, id, message, status, runLayout) =>
                  Container(
                    key: ValueKey('row-$id'),
                    height: 120,
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          height: 60,
                          child: markdown
                              ? ChatMarkdownBody(
                                  controller: selection,
                                  messageId: id,
                                )
                              : Text('row $id'),
                        ),
                        ChatMessageTapBarrier(
                          enabled: barrierEnabled,
                          child: const SizedBox(
                            key: ValueKey('barrier'),
                            width: 80,
                            height: 30,
                          ),
                        ),
                      ],
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _Rig(selection, idle, secondary);
  }

  Offset beside(WidgetTester tester, int id) =>
      tester.getBottomRight(barrierOf(id)) + const Offset(150, -15);

  /// A press-and-lift of [kind] with [buttons] at [at].
  Future<void> press(
    WidgetTester tester,
    Offset at, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
    int buttons = kPrimaryButton,
  }) async {
    final gesture = await tester.createGesture(kind: kind, buttons: buttons);
    if (kind == PointerDeviceKind.mouse) await gesture.addPointer(location: at);
    await gesture.down(at);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    if (kind == PointerDeviceKind.mouse) await gesture.removePointer();
  }

  group('under the desktop policy, with a mouse', () {
    const desktop = ChatSelectionPolicy.desktop();

    testWidgets('a click on the barrier does not toggle a row, and one '
        'beside it does', (tester) async {
      final rig = await mount(tester, policy: desktop);
      rig.selection
        ..startSelection(0)
        ..toggle(1);
      await tester.pump();

      await press(tester, tester.getCenter(barrierOf(1)));
      expect(rig.selection.selectedIds, <int>{0, 1});

      await press(tester, beside(tester, 1));
      expect(rig.selection.selectedIds, <int>{0});
    });

    testWidgets('a click on the barrier does not add a row to a live '
        'selection', (tester) async {
      final rig = await mount(tester, policy: desktop);
      rig.selection.startSelection(0);
      await tester.pump();

      await press(tester, tester.getCenter(barrierOf(1)));

      expect(rig.selection.selectedIds, <int>{0});
    });

    testWidgets('a drag that starts on the barrier selects nothing, and one '
        'that starts beside it does', (tester) async {
      final rig = await mount(tester, policy: desktop);
      final start = tester.getCenter(barrierOf(1));

      final barred = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await barred.moveTo(start + const Offset(0, -150));
      await tester.pump();
      await barred.up();
      await tester.pump();
      expect(rig.selection.selectedIds, isEmpty);

      final free = await tester.startGesture(
        beside(tester, 1),
        kind: PointerDeviceKind.mouse,
      );
      await free.moveTo(beside(tester, 1) + const Offset(0, -150));
      await tester.pump();
      await free.up();
      await tester.pump();
      expect(rig.selection.selectedIds, isNotEmpty);
    });

    testWidgets('a secondary click on the barrier reaches the message menu '
        'callback, as one beside it does', (tester) async {
      final rig = await mount(tester, policy: desktop);

      await press(
        tester,
        tester.getCenter(barrierOf(1)),
        buttons: kSecondaryButton,
      );
      await press(tester, beside(tester, 1), buttons: kSecondaryButton);

      expect(rig.secondary, <int>[1, 1]);
    });

    testWidgets('a disabled barrier is part of the message', (tester) async {
      final rig = await mount(tester, policy: desktop, barrierEnabled: false);
      rig.selection.startSelection(0);
      await tester.pump();

      await press(tester, tester.getCenter(barrierOf(1)));

      expect(rig.selection.selectedIds, <int>{0, 1});
    });

    testWidgets('a pointer that is not a barrier press leaves no bar behind', (
      tester,
    ) async {
      final rig = await mount(tester, policy: desktop);
      rig.selection.startSelection(0);
      await tester.pump();

      // Down on the barrier, lift, and a later press beside it: the second
      // press is not barred.
      await press(tester, tester.getCenter(barrierOf(1)));
      await press(tester, beside(tester, 1));

      expect(rig.selection.selectedIds, <int>{0, 1});
    });
  });

  group('under the mobile policy', () {
    const mobile = ChatSelectionPolicy.mobile();

    testWidgets('a touch tap on the barrier is a message tap', (tester) async {
      final rig = await mount(tester, policy: mobile);

      await press(
        tester,
        tester.getCenter(barrierOf(1)),
        kind: PointerDeviceKind.touch,
      );
      expect(rig.idle, <int>[1]);

      rig.selection.startSelection(0);
      await tester.pump();
      await press(
        tester,
        tester.getCenter(barrierOf(1)),
        kind: PointerDeviceKind.touch,
      );
      expect(rig.selection.selectedIds, <int>{0, 1});
    });

    testWidgets('a mouse click on the barrier is not a message tap, and one '
        'beside it is', (tester) async {
      final rig = await mount(tester, policy: mobile);

      await press(tester, tester.getCenter(barrierOf(1)));
      expect(rig.idle, isEmpty);

      await press(tester, beside(tester, 1));
      expect(rig.idle, <int>[1]);
    });

    testWidgets('a tap on the barrier still dismisses text selection and '
        'keeps the selected rows', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final rig = await mount(tester, policy: mobile, markdown: true);
        rig.selection.startSelection(1);
        await tester.pumpAndSettle();
        final inBody =
            tester.getTopLeft(
              find.descendant(
                of: find.byKey(const ValueKey('row-1')),
                matching: find.byType(MarkdownWidget),
              ),
            ) +
            const Offset(24, 16);
        expect(
          rig.selection.enterTextSelection(1, globalOffset: inBody),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(rig.selection.isTextSelectionActive, isTrue);

        await press(tester, tester.getCenter(barrierOf(1)));
        await tester.pumpAndSettle();

        expect(rig.selection.isTextSelectionActive, isFalse);
        expect(rig.selection.selectedIds, <int>{1});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
