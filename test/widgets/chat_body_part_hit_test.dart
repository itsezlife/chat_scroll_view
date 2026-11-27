/// A body part hit (`ChatInlineHit.bodyPart`) is arbitrated against message
/// selection like a sticker, and the touched part reaches the message menu.
///
/// **Seam:** [ChatSelectionController] and a mounted [ChatScrollView] whose
/// rows register a fake non-text body with two parts (an `activate` part on
/// the left half, a `menu` part on the right); observed through the
/// interactions, the menu requests, the selected set and the diagnostics
/// events. The part ids are opaque values of the test's own.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart'
    show ChatEventCategory, ChatEventLevel;
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

/// An opaque part id that names itself in diagnostics.
@immutable
final class _Part implements ChatDiagnosablePart {
  const _Part(this.item, this.name);

  final String item;
  final String name;

  @override
  String get diagnosticName => name;

  @override
  String? get diagnosticItemId => item;

  @override
  bool operator ==(Object other) =>
      other is _Part && other.item == item && other.name == name;

  @override
  int get hashCode => Object.hash(item, name);
}

/// An opaque part id with no diagnostics of its own.
const _plainPart = #plain;

const _rect = Rect.fromLTWH(10, 20, 100, 100);

const _activateHit = ChatInlineHit.bodyPart(
  messageId: 1,
  partId: _Part('a', 'content'),
  role: ChatBodyPartRole.activate,
  rect: _rect,
);

const _menuHit = ChatInlineHit.bodyPart(
  messageId: 1,
  partId: _Part('a', 'options'),
  role: ChatBodyPartRole.menu,
  rect: _rect,
);

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content',
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
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

/// A body that paints no text: its left half is an `activate` part, its
/// right half a `menu` part, each with an id naming the message.
class _PartsBody extends StatefulWidget {
  const _PartsBody({
    required this.selection,
    required this.messageId,
    this.plainIds = false,
  });

  final ChatSelectionController selection;
  final int messageId;

  /// Whether the parts carry ids that do not name themselves.
  final bool plainIds;

  @override
  State<_PartsBody> createState() => _PartsBodyState();
}

class _PartsBodyState extends State<_PartsBody> implements ChatNonTextBody {
  Object? _token;

  @override
  void initState() {
    super.initState();
    _token = widget.selection.putNonTextBody(widget.messageId, this);
  }

  @override
  void dispose() {
    widget.selection.removeNonTextBody(widget.messageId, token: _token);
    super.dispose();
  }

  @override
  Rect? get globalBounds => switch (context.findRenderObject()) {
    final RenderBox box when box.hasSize && box.attached =>
      box.localToGlobal(Offset.zero) & box.size,
    _ => null,
  };

  @override
  ChatInlineHit? inlineHitAt(Offset globalOffset) {
    final bounds = globalBounds;
    if (bounds == null || !bounds.contains(globalOffset)) return null;
    final left = globalOffset.dx < bounds.center.dx;
    final rect = left
        ? Rect.fromLTRB(
            bounds.left,
            bounds.top,
            bounds.center.dx,
            bounds.bottom,
          )
        : Rect.fromLTRB(
            bounds.center.dx,
            bounds.top,
            bounds.right,
            bounds.bottom,
          );
    return ChatInlineHit.bodyPart(
      messageId: widget.messageId,
      partId: widget.plainIds
          ? _plainPart
          : _Part('m${widget.messageId}', left ? 'content' : 'options'),
      role: left ? ChatBodyPartRole.activate : ChatBodyPartRole.menu,
      rect: rect,
    );
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('body-${widget.messageId}'),
    width: 200,
    height: 60,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ChatSelectionInteraction> heard;
  late RecordingDiagnostics diagnostics;

  setUp(() {
    heard = [];
    diagnostics = RecordingDiagnostics.install();
  });

  ChatSelectionController facade({
    ChatSelectionPolicy policy = const ChatSelectionPolicy.mobile(),
  }) {
    final selection = ChatSelectionController(
      policy: policy,
      onInteraction: heard.add,
      chatId: 'chat-1',
    );
    addTearDown(selection.dispose);
    return selection;
  }

  group('the hit', () {
    test('has value equality, no contour, and a toString with its role', () {
      expect(
        const ChatInlineHit.bodyPart(
          messageId: 1,
          partId: _Part('a', 'content'),
          role: ChatBodyPartRole.activate,
          rect: _rect,
        ),
        _activateHit,
      );
      expect(_activateHit, isNot(_menuHit));
      expect(
        const ChatInlineHit.bodyPart(
          messageId: 1,
          partId: _Part('a', 'content'),
          role: ChatBodyPartRole.activate,
          rect: Rect.zero,
        ),
        isNot(_activateHit),
      );
      expect(_activateHit.contourPath, isNull);
      expect(_activateHit.touchOrigin, isNull);
      expect(_menuHit.toString(), contains('role: menu'));
    });

    test('the activation has value equality', () {
      expect(
        const ChatSelectionInteraction.bodyPartActivated(
          messageId: 1,
          partId: _plainPart,
          rect: _rect,
        ),
        const ChatBodyPartActivated(
          messageId: 1,
          partId: _plainPart,
          rect: _rect,
        ),
      );
    });
  });

  group('the facade', () {
    for (final policy in const [
      ChatSelectionPolicy.mobile(),
      ChatSelectionPolicy.desktop(),
    ]) {
      final name = policy.runtimeType.toString();

      test('$name: an activate part is reported to the host', () {
        final selection = facade(policy: policy);

        expect(selection.handleInlineHit(_activateHit), isTrue);

        expect(heard, [
          const ChatBodyPartActivated(
            messageId: 1,
            partId: _Part('a', 'content'),
            rect: _rect,
          ),
        ]);
      });

      test('$name: a menu part is left to the viewport\'s menu', () {
        final selection = facade(policy: policy);

        expect(selection.handleInlineHit(_menuHit), isFalse);
        expect(heard, isEmpty);
      });

      test('$name: in message selection no part activates', () {
        final selection = facade(policy: policy)..startSelection(2);

        expect(selection.handleInlineHit(_activateHit), isFalse);
        expect(selection.handleInlineHit(_menuHit), isFalse);
        expect(heard, isEmpty);
      });

      test('$name: a long press on a part is the message\'s', () {
        final selection = facade(policy: policy);

        expect(selection.handleInlineHitLongPress(_activateHit), isFalse);
        expect(selection.handleInlineHitLongPress(_menuHit), isFalse);
        expect(heard, isEmpty);
      });
    }
  });

  group('the menu request', () {
    test('carries the part id of a body part hit, and none otherwise', () {
      ChatMessageMenuRequest request(ChatInlineHit? hit) =>
          ChatMessageMenuRequest(
            messageId: 1,
            slotGlobal: _rect,
            tapGlobal: _rect.center,
            inlineHit: hit,
          );

      expect(request(_menuHit).partId, const _Part('a', 'options'));
      expect(request(null).partId, isNull);
      expect(
        request(
          const ChatInlineHit.link(messageId: 1, title: 't', url: 'u'),
        ).partId,
        isNull,
      );
    });
  });

  group('in the viewport', () {
    late List<ChatMessageMenuRequest> idleRequests;
    late List<ChatMessageMenuRequest> secondaryRequests;

    setUp(() {
      idleRequests = [];
      secondaryRequests = [];
    });

    Future<ChatSelectionController> pump(
      WidgetTester tester, {
      ChatSelectionPolicy policy = const ChatSelectionPolicy.mobile(),
      bool plainIds = false,
    }) async {
      final selection = facade(policy: policy);
      final dataSource = _LoadedSource([_msg(1), _msg(2)]);
      final controller = ChatScrollController();
      addTearDown(controller.dispose);
      addTearDown(dataSource.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatScrollView(
                dataSource: dataSource,
                controller: controller,
                selectionController: selection,
                onIdleMessageTap: idleRequests.add,
                onSecondaryMessageTap: secondaryRequests.add,
                messageBuilder: (context, id, message, status, runLayout) =>
                    SizedBox(
                      height: 80,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _PartsBody(
                          selection: selection,
                          messageId: id,
                          plainIds: plainIds,
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return selection;
    }

    Offset activateAt(WidgetTester tester, [int id = 1]) =>
        tester.getRect(find.byKey(ValueKey('body-$id'))).centerLeft +
        const Offset(40, 0);

    Offset menuAt(WidgetTester tester, [int id = 1]) =>
        tester.getRect(find.byKey(ValueKey('body-$id'))).centerRight -
        const Offset(40, 0);

    void expectHitEvent({
      required String part,
      required String role,
      required String mode,
      required String outcome,
      int messageId = 1,
    }) {
      final event = diagnostics.whereOp(ChatSelectionOp.hit).single;
      expect(event.category, ChatEventCategory.media);
      expect(event.level, ChatEventLevel.debug);
      expect(event.correlation.chatId, 'chat-1');
      expect(event.correlation.scrollId, '$messageId');
      expect(event.correlation.mediaItemId, 'm$messageId');
      expect(event.fields['part'], part);
      expect((event.fields['role']! as Enum).name, role);
      expect(event.fields['mode'], mode);
      expect((event.fields['outcome']! as Enum).name, outcome);
    }

    testWidgets('mobile: a tap on an activate part reaches the host and opens '
        'no menu', (tester) async {
      await pump(tester);

      await tester.tapAt(activateAt(tester));
      await tester.pump();

      expect(heard, [
        isA<ChatBodyPartActivated>()
            .having((a) => a.messageId, 'messageId', 1)
            .having((a) => a.partId, 'partId', const _Part('m1', 'content')),
      ]);
      expect(idleRequests, isEmpty);
      expectHitEvent(
        part: 'content',
        role: 'activate',
        mode: 'normal',
        outcome: 'activate',
      );
    });

    testWidgets('mobile: a tap on a menu part opens the menu with the part', (
      tester,
    ) async {
      await pump(tester);

      await tester.tapAt(menuAt(tester));
      await tester.pump();

      expect(heard, isEmpty);
      expect(idleRequests.single.messageId, 1);
      expect(idleRequests.single.partId, const _Part('m1', 'options'));
      expect(secondaryRequests, isEmpty);
      expectHitEvent(
        part: 'options',
        role: 'menu',
        mode: 'normal',
        outcome: 'menu',
      );
    });

    testWidgets('desktop: a click on a menu part opens the menu as a '
        'secondary click does', (tester) async {
      await pump(tester, policy: const ChatSelectionPolicy.desktop());

      await tester.tapAt(menuAt(tester));
      await tester.pump();

      expect(secondaryRequests.single.partId, const _Part('m1', 'options'));
      expect(idleRequests, isEmpty);
      expect(heard, isEmpty);
    });

    testWidgets('desktop: a secondary click on an activate part opens the '
        'menu with that part, and activates nothing', (tester) async {
      await pump(tester, policy: const ChatSelectionPolicy.desktop());

      await tester.tapAt(activateAt(tester), buttons: kSecondaryMouseButton);
      await tester.pump();

      expect(secondaryRequests.single.partId, const _Part('m1', 'content'));
      expect(heard, isEmpty);
      expectHitEvent(
        part: 'content',
        role: 'activate',
        mode: 'normal',
        outcome: 'menu',
      );
    });

    for (final policy in const [
      ChatSelectionPolicy.mobile(),
      ChatSelectionPolicy.desktop(),
    ]) {
      final name = policy.runtimeType.toString();

      testWidgets('$name: in message selection every part toggles', (
        tester,
      ) async {
        final selection = await pump(tester, policy: policy);
        selection.startSelection(2);

        await tester.tapAt(activateAt(tester));
        await tester.pump();
        expect(selection.selectedIds, {1, 2});
        expectHitEvent(
          part: 'content',
          role: 'activate',
          mode: 'selection',
          outcome: 'toggle',
        );
        diagnostics.clear();

        await tester.tapAt(menuAt(tester));
        await tester.pump();
        expect(selection.selectedIds, {2});
        expectHitEvent(
          part: 'options',
          role: 'menu',
          mode: 'selection',
          outcome: 'toggle',
        );

        expect(heard, isEmpty);
        expect(idleRequests, isEmpty);
        expect(secondaryRequests, isEmpty);
      });
    }

    testWidgets('mobile: a long press on a part is the message\'s: it starts '
        'message selection and activates nothing', (tester) async {
      final selection = await pump(tester);

      await tester.longPressAt(activateAt(tester));
      await tester.pumpAndSettle();
      expect(selection.selectedIds, {1});

      await tester.longPressAt(menuAt(tester, 2));
      await tester.pumpAndSettle();
      expect(selection.selectedIds, {1, 2});

      expect(heard, isEmpty);
      expect(idleRequests, isEmpty);
    });

    testWidgets('a long press on a part reports the hit as the message\'s', (
      tester,
    ) async {
      await pump(tester);

      await tester.longPressAt(activateAt(tester));
      await tester.pumpAndSettle();

      final event = diagnostics.whereOp(ChatSelectionOp.hit).single;
      expect(event.fields['gesture'], ChatBodyPartGesture.longPress);
      expect(event.fields['mode'], 'normal');
      expect(event.fields['outcome'], ChatBodyPartOutcome.toggle);
      expect(event.fields['part'], 'content');
      expect(event.correlation.mediaItemId, 'm1');
    });

    testWidgets('a tap and a secondary click name their gesture', (
      tester,
    ) async {
      await pump(tester, policy: const ChatSelectionPolicy.desktop());

      await tester.tapAt(activateAt(tester));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(activateAt(tester), buttons: kSecondaryMouseButton);
      await tester.pump();

      expect(
        diagnostics
            .whereOp(ChatSelectionOp.hit)
            .map((event) => event.fields['gesture']),
        [ChatBodyPartGesture.tap, ChatBodyPartGesture.secondaryTap],
      );
    });

    testWidgets('a part id that names nothing logs no part and no item', (
      tester,
    ) async {
      await pump(tester, plainIds: true);

      await tester.tapAt(activateAt(tester));
      await tester.pump();

      expect((heard.single as ChatBodyPartActivated).partId, _plainPart);
      final event = diagnostics.whereOp(ChatSelectionOp.hit).single;
      expect(event.fields.containsKey('part'), isFalse);
      expect(event.correlation.mediaItemId, isNull);
      expect(event.correlation.scrollId, '1');
    });
  });
}
