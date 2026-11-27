/// Media in a chat list: the body part hits of its items, what a tap on
/// each does per platform, the menu request's part, message selection, the
/// input guard, the viewer's origin frames, the mouse and the semantics.
///
/// **Seam:** `MessageMediaView` rows of a mounted `ChatScrollView` with a
/// `ChatSelectionController` (clock injected), over a `ContentAssetScope`
/// whose media producer is a `FakeAssetProducer` (the test reports each
/// item's download); observed through the viewer requests, the menu
/// requests, the selected set, the producer's attempts, the chat's
/// `MessageMediaState`, the semantics tree and `RecordingDiagnostics`.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart' hide RecordingDiagnostics;

MediaItem _item(
  String id, {
  MediaItemKind kind = MediaItemKind.photo,
  bool spoiler = false,
  int? byteSize = 2048,
  Duration? duration,
}) => MediaItem(
  id: MediaItemId(id),
  kind: kind,
  spoiler: spoiler,
  descriptor: ContentDescriptor(
    key: ContentKey.document('doc-$id'),
    size: const ContentSize(4, 3),
    byteSize: byteSize,
    duration: duration,
    fileName: 'private-$id.jpg',
  ),
);

final class _Message implements IChatMessage {
  _Message(this.id);

  @override
  final int id;

  @override
  String get sender => 'host';

  @override
  DateTime get createdAt => DateTime(2026);

  @override
  DateTime get updatedAt => DateTime(2026);
}

final class _Source extends ChatDataSource {
  _Source(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_Message(i));
    }
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

const _count = 8;
const _last = _count - 1;

void main() {
  late FakeAssetProducer producer;
  late ContentAssetScope scope;
  late MessageMediaState state;
  late RecordingDiagnostics diagnostics;
  late List<MediaViewerRequest> opened;
  late List<ChatMessageMenuRequest> idleMenus;
  late List<ChatMessageMenuRequest> secondaryMenus;
  late Duration now;

  setUp(() {
    producer = FakeAssetProducer();
    scope = ContentAssetScope.withMedia(producer: producer);
    state = MessageMediaState();
    diagnostics = RecordingDiagnostics.install();
    opened = [];
    idleMenus = [];
    secondaryMenus = [];
    now = Duration.zero;
    addTearDown(scope.dispose);
    addTearDown(state.dispose);
  });

  // The items of message [id]: an album of two pictures on the last one, a
  // single picture on the others, unless [itemsOf] says otherwise.
  List<MediaItem> defaultItemsOf(int id) =>
      id == _last ? [_item('$id-a'), _item('$id-b')] : [_item('$id-a')];

  late ChatSelectionController selection;
  late ChatScrollController controller;
  late MessageMediaPolicy media;

  MediaLayout layoutOf(List<MediaItem> items) => media.layout(
    MediaLayoutInput(
      items: items,
      availableWidth: 300,
      displaySize: const Size(400, 640),
    ),
  );

  Future<void> pump(
    WidgetTester tester, {
    MessageMediaPolicy policy = const MessageMediaPolicy.android(),
    ChatSelectionPolicy selectionPolicy = const ChatSelectionPolicy.mobile(),
    List<MediaItem> Function(int id)? itemsOf,
    void Function(MediaHitPart part, Rect rect)? onItemMenu,
  }) async {
    media = policy;
    selection = ChatSelectionController(
      policy: selectionPolicy,
      chatId: 'chat-1',
      monotonicClock: () => now,
    );
    controller = ChatScrollController()..jumpTo(_last);
    final source = _Source(_count);
    addTearDown(selection.dispose);
    addTearDown(controller.dispose);
    addTearDown(source.dispose);
    final items = itemsOf ?? defaultItemsOf;
    await tester.pumpWidget(
      MaterialApp(
        home: ContentAssetProvider(
          scope: scope,
          child: MessageMediaStateScope(
            state: state,
            child: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: ChatScrollView(
                  dataSource: source,
                  controller: controller,
                  selectionController: selection,
                  onIdleMessageTap: idleMenus.add,
                  onSecondaryMessageTap: secondaryMenus.add,
                  messageBuilder: (context, id, message, status, runLayout) {
                    final list = items(id);
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: MessageMediaView(
                        layout: layoutOf(list),
                        items: list,
                        policy: policy,
                        selection: selection,
                        messageId: id,
                        onOpenViewer: opened.add,
                        onItemMenu: onItemMenu,
                        correlation: ChatCorrelation(
                          chatId: 'chat-1',
                          scrollId: '$id',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // A spoiler's cover moves for ever: settle by time, not by frames.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Finder cellOf(String id) => find.byKey(ValueKey(MediaItemId(id)));

  Rect rectOf(WidgetTester tester, String id) => tester.getRect(cellOf(id));

  // The top-left corner of a cell, away from its status control.
  Offset contentAt(WidgetTester tester, String id) =>
      rectOf(tester, id).topLeft + const Offset(8, 8);

  Offset statusAt(WidgetTester tester, String id) => rectOf(tester, id).center;

  FakeAssetAttempt attemptOf(String id) => producer.attempts.firstWhere(
    (attempt) => attempt.request.key == ContentKey.document('doc-$id').mediaKey,
  );

  AssetTransfer transferOf(String id) {
    final binding = scope.media.attach(
      ContentKey.document('doc-$id').mediaKey,
      attemptOf(id).request.spec,
      const AssetProfile(),
    );
    final transfer = binding.transfer;
    binding.detach();
    return transfer;
  }

  Future<void> tap(WidgetTester tester, Offset at, {int? buttons}) async {
    await tester.tapAt(at, buttons: buttons ?? kPrimaryButton);
    await tester.pump();
  }

  // Moves the injected clock past the input guard.
  void later() => now += const Duration(seconds: 1);

  ChatInlineHit$BodyPart hitAt(WidgetTester tester, int id, Offset at) =>
      selection.resolveInlineHit(id, at)! as ChatInlineHit$BodyPart;

  group('the parts', () {
    testWidgets('content, status, spoiler and options each answer with '
        'their role and global rect', (tester) async {
      await pump(
        tester,
        itemsOf: (id) => [
          _item('$id-photo'),
          _item('$id-hidden', spoiler: true),
          _item('$id-video', kind: MediaItemKind.video),
        ],
      );
      const id = _last;
      attemptOf('$id-photo').awaitingUser();
      await tester.pump();

      final status = hitAt(tester, id, statusAt(tester, '$id-photo'));
      expect(
        status.partId,
        const MediaHitPart(MediaItemId('$_last-photo'), part: MediaPart.status),
      );
      expect(status.role, ChatBodyPartRole.activate);
      expect(status.rect.center, rectOf(tester, '$id-photo').center);

      final content = hitAt(tester, id, contentAt(tester, '$id-photo'));
      expect((content.partId as MediaHitPart).part, MediaPart.content);
      expect(content.rect, rectOf(tester, '$id-photo'));

      final spoiler = hitAt(tester, id, statusAt(tester, '$id-hidden'));
      expect((spoiler.partId as MediaHitPart).part, MediaPart.spoiler);
      expect(spoiler.role, ChatBodyPartRole.activate);

      final video = rectOf(tester, '$id-video');
      final layout = layoutOf([
        _item('$id-photo'),
        _item('$id-hidden', spoiler: true),
        _item('$id-video', kind: MediaItemKind.video),
      ]);
      final block = layout.blocks.single;
      final cell = block.cells.firstWhere(
        (cell) => cell.itemId == const MediaItemId('$id-video'),
      );
      final affordance = media.chrome.options.affordanceOf(cell, block)!;
      final viewOrigin = video.topLeft - cell.rect.topLeft;
      final options = hitAt(
        tester,
        id,
        viewOrigin + affordance.iconRect.center,
      );
      expect((options.partId as MediaHitPart).part, MediaPart.options);
      expect(options.role, ChatBodyPartRole.menu);
      expect(options.rect, affordance.hitRect.shift(viewOrigin));
    });

    testWidgets('a status control showing nothing is content', (tester) async {
      await pump(tester);
      attemptOf('$_last-a').advance(AssetStage.full);
      await tester.pump();

      final hit = hitAt(tester, _last, statusAt(tester, '$_last-a'));
      expect((hit.partId as MediaHitPart).part, MediaPart.content);
    });
  });

  group('normal mode', () {
    testWidgets('a tap on the content opens the viewer on the album, from '
        'the cell\'s rect', (tester) async {
      await pump(tester);

      await tap(tester, contentAt(tester, '$_last-b'));

      final request = opened.single;
      expect(request.messageId, _last);
      expect(request.items, const [
        MediaItemId('$_last-a'),
        MediaItemId('$_last-b'),
      ]);
      expect(request.index, 1);
      expect(request.originRect, rectOf(tester, '$_last-b'));
      final event = diagnostics.whereOp(MediaOp.viewerOpened).single;
      expect(event.level, ChatEventLevel.info);
      expect(event.fields, {'index': 1, 'count': 2});
      expect(event.correlation.mediaItemId, '${const MediaItemId('$_last-b')}');
      expect(event.correlation.scrollId, '$_last');
    });

    testWidgets('android: a loading picture opens the viewer; only the '
        'status control cancels', (tester) async {
      await pump(tester);
      attemptOf('$_last-a').transfer(10, 100);
      await tester.pump();

      await tap(tester, contentAt(tester, '$_last-a'));
      expect(opened, hasLength(1));
      expect(attemptOf('$_last-a').isCancelled, isFalse);

      later();
      await tap(tester, statusAt(tester, '$_last-a'));
      expect(attemptOf('$_last-a').isCancelled, isTrue);
      expect(opened, hasLength(1));
      final event = diagnostics.whereOp(MediaOp.hit).single;
      expect(event.fields['outcome'], 'cancel');
      expect(event.fields['part'], 'status');
    });

    for (final policy in const [
      MessageMediaPolicy.ios(),
      MessageMediaPolicy.desktop(),
    ]) {
      testWidgets('${policy.family.name}: a tap anywhere on a loading '
          'picture cancels it', (tester) async {
        await pump(tester, policy: policy);
        attemptOf('$_last-a').transfer(10, 100);
        await tester.pump();

        await tap(tester, contentAt(tester, '$_last-a'));

        expect(attemptOf('$_last-a').isCancelled, isTrue);
        expect(opened, isEmpty);
        expect(
          diagnostics.whereOp(MediaOp.hit).single.fields['outcome'],
          'cancel',
        );
      });
    }

    testWidgets('the status control downloads what waits for the user', (
      tester,
    ) async {
      await pump(tester);
      attemptOf('$_last-a').awaitingUser();
      await tester.pump();
      final before = producer.attempts.length;

      await tap(tester, statusAt(tester, '$_last-a'));

      // The user's download starts a fresh attempt at the content.
      expect(producer.attempts.length, greaterThan(before));
      expect(opened, isEmpty);
      expect(
        (hitAt(tester, _last, statusAt(tester, '$_last-a')).partId
                as MediaHitPart)
            .part,
        MediaPart.content,
      );
    });

    testWidgets('a hidden spoiler takes the first tap and only reveals', (
      tester,
    ) async {
      await pump(tester, itemsOf: (id) => [_item('$id-s', spoiler: true)]);
      const item = MediaItemId('$_last-s');

      await tap(tester, contentAt(tester, '$_last-s'));

      expect(state.isSpoilerRevealed(item), isTrue);
      expect(opened, isEmpty);
      final event = diagnostics.whereOp(MediaOp.hit).single;
      expect(event.fields['outcome'], 'reveal');
      expect(event.fields['part'], 'spoiler');

      await tester.pump(const Duration(seconds: 1));
      later();
      await tap(tester, contentAt(tester, '$_last-s'));
      expect(opened.single.item, item);
    });

    testWidgets('android: a tap on the options affordance opens the menu '
        'with the part', (tester) async {
      await pump(
        tester,
        itemsOf: (id) => [_item('$id-v', kind: MediaItemKind.video)],
      );
      final layout = layoutOf([_item('$_last-v', kind: MediaItemKind.video)]);
      final block = layout.blocks.single;
      final affordance = media.chrome.options.affordanceOf(
        block.cells.single,
        block,
      )!;

      await tap(
        tester,
        rectOf(tester, '$_last-v').topLeft + affordance.iconRect.center,
      );

      expect(
        idleMenus.single.partId,
        const MediaHitPart(MediaItemId('$_last-v'), part: MediaPart.options),
      );
      expect(opened, isEmpty);
    });

    testWidgets('desktop: a secondary click on the content opens the menu '
        'with the part', (tester) async {
      await pump(
        tester,
        policy: const MessageMediaPolicy.desktop(),
        selectionPolicy: const ChatSelectionPolicy.desktop(),
      );

      await tap(
        tester,
        contentAt(tester, '$_last-a'),
        buttons: kSecondaryMouseButton,
      );

      expect(
        secondaryMenus.single.partId,
        const MediaHitPart(MediaItemId('$_last-a'), part: MediaPart.content),
      );
      expect(opened, isEmpty);
    });
  });

  group('message selection', () {
    testWidgets('every part toggles the message and acts on nothing', (
      tester,
    ) async {
      await pump(
        tester,
        itemsOf: (id) => [_item('$id-a'), _item('$id-s', spoiler: true)],
      );
      attemptOf('$_last-a').transfer(10, 100);
      await tester.pump();
      selection.startSelection(0);
      await tester.pump();

      await tap(tester, contentAt(tester, '$_last-a'));
      expect(selection.selectedIds, {0, _last});
      later();
      await tap(tester, statusAt(tester, '$_last-a'));
      expect(selection.selectedIds, {0});
      later();
      await tap(tester, contentAt(tester, '$_last-s'));
      expect(selection.selectedIds, {0, _last});

      expect(opened, isEmpty);
      expect(attemptOf('$_last-a').isCancelled, isFalse);
      expect(state.isSpoilerRevealed(const MediaItemId('$_last-s')), isFalse);
      expect(diagnostics.whereOp(MediaOp.hit), isEmpty);
    });
  });

  group('the input guard', () {
    testWidgets('a burst of taps on the content opens the viewer once', (
      tester,
    ) async {
      await pump(tester);

      for (var i = 0; i < 3; i++) {
        await tap(tester, contentAt(tester, '$_last-a'));
        now += const Duration(milliseconds: 100);
        await tester.pump(const Duration(milliseconds: 400));
      }

      expect(opened, hasLength(1));
      final dropped = diagnostics.whereOp(MediaOp.activationDropped);
      expect(dropped, hasLength(2));
      expect(dropped.first.fields, {'part': 'content', 'sinceMs': 100});
      expect(
        dropped.first.correlation.mediaItemId,
        '${const MediaItemId('$_last-a')}',
      );

      later();
      await tap(tester, contentAt(tester, '$_last-a'));
      expect(opened, hasLength(2));
    });

    testWidgets('a double tap on the status control cancels once and does '
        'not download again', (tester) async {
      await pump(tester);
      attemptOf('$_last-a').transfer(10, 100);
      await tester.pump();

      await tap(tester, statusAt(tester, '$_last-a'));
      now += const Duration(milliseconds: 150);
      await tester.pump(const Duration(milliseconds: 400));
      await tap(tester, statusAt(tester, '$_last-a'));

      expect(transferOf('$_last-a'), isA<AssetTransfer$AwaitingUser>());
      expect(diagnostics.whereOp(MediaOp.activationDropped), hasLength(1));
    });
  });

  group('the origin frame', () {
    testWidgets('neighbours answer by id after a scroll, and an item off '
        'screen answers none', (tester) async {
      await pump(tester);
      await tap(tester, contentAt(tester, '$_last-a'));
      final request = opened.single;

      await tester.drag(find.byType(ChatScrollView), const Offset(0, 120));
      await tester.pumpAndSettle();

      expect(
        request.rectOf(const MediaItemId('$_last-b')),
        rectOf(tester, '$_last-b'),
      );
      expect(diagnostics.whereOp(MediaOp.originRectMissing), isEmpty);

      controller.jumpTo(0);
      await tester.pumpAndSettle();
      expect(cellOf('$_last-b'), findsNothing);
      expect(request.rectOf(const MediaItemId('$_last-b')), isNull);
      final missing = diagnostics.whereOp(MediaOp.originRectMissing).single;
      expect(missing.level, ChatEventLevel.warning);
      expect(missing.fields, {'at': 'close'});
    });
  });

  group('the mouse', () {
    Future<TestGesture> hover(WidgetTester tester, Offset at) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(at);
      await tester.pump();
      return mouse;
    }

    MouseCursor cursor() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;

    double highlightOf(WidgetTester tester, String id) => tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: cellOf(id),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    testWidgets('desktop: the click cursor and the highlight over a part, '
        'plain in selection', (tester) async {
      await pump(
        tester,
        policy: const MessageMediaPolicy.desktop(),
        selectionPolicy: const ChatSelectionPolicy.desktop(),
      );

      final mouse = await hover(tester, contentAt(tester, '$_last-a'));
      expect(cursor(), SystemMouseCursors.click);
      expect(highlightOf(tester, '$_last-a'), 1);
      expect(highlightOf(tester, '$_last-b'), 0);

      selection.startSelection(_last);
      await tester.pump();
      expect(cursor(), isNot(SystemMouseCursors.click));
      expect(highlightOf(tester, '$_last-a'), 0);

      selection.clear();
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(highlightOf(tester, '$_last-a'), 0);
    });

    testWidgets('android: no click cursor and no highlight', (tester) async {
      await pump(tester);

      await hover(tester, contentAt(tester, '$_last-a'));

      expect(cursor(), isNot(SystemMouseCursors.click));
      expect(
        find.descendant(
          of: cellOf('$_last-a'),
          matching: find.byType(AnimatedOpacity),
        ),
        findsNothing,
      );
    });
  });

  group('semantics', () {
    SemanticsNode nodeOf(WidgetTester tester, Pattern label) =>
        tester.getSemantics(find.bySemanticsLabel(label));

    testWidgets('one node per item: kind, size or duration, progress; the '
        'status control and the options as actions', (tester) async {
      final handle = tester.ensureSemantics();
      final menus = <MediaHitPart>[];
      await pump(
        tester,
        onItemMenu: (part, rect) => menus.add(part),
        itemsOf: (id) => [
          _item('$id-p'),
          _item(
            '$id-v',
            kind: MediaItemKind.video,
            duration: const Duration(seconds: 65),
          ),
          _item('$id-f', kind: MediaItemKind.file, byteSize: 3 * 1024 * 1024),
        ],
      );
      attemptOf('$_last-p').transfer(50, 100);
      attemptOf('$_last-v').advance(AssetStage.full);
      await tester.pump();

      final photo = nodeOf(tester, 'Photo, 2.0 KB, Downloading, 50%');
      expect(
        photo,
        matchesSemantics(
          label: 'Photo, 2.0 KB, Downloading, 50%',
          hasTapAction: true,
          customActions: const [
            CustomSemanticsAction(label: 'Cancel download'),
          ],
        ),
      );
      expect(
        nodeOf(tester, 'Video, 1:05'),
        matchesSemantics(
          label: 'Video, 1:05',
          hasTapAction: true,
          customActions: const [CustomSemanticsAction(label: 'More options')],
        ),
      );
      expect(find.bySemanticsLabel(RegExp(r'^File, 3\.0 MB$')), findsWidgets);

      final owner = photo.owner!;
      owner.performAction(photo.id, SemanticsAction.tap);
      await tester.pump();
      expect(opened.single.item, const MediaItemId('$_last-p'));

      final video = nodeOf(tester, 'Video, 1:05');
      final options = CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'More options'),
      );
      owner.performAction(video.id, SemanticsAction.customAction, options);
      expect(menus.single.part, MediaPart.options);
      handle.dispose();
    });

    testWidgets('in message selection the node\'s action is the toggle', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      attemptOf('$_last-a').transfer(50, 100);
      // A selected row: the viewport keeps an unselected row's children from
      // pointers (and their semantics actions) on mobile.
      selection
        ..startSelection(0)
        ..toggle(_last);
      await tester.pump();
      final node = tester.getSemantics(
        find.bySemanticsLabel('Photo, 2.0 KB, Downloading, 50%').first,
      );
      expect(
        node,
        matchesSemantics(
          label: 'Photo, 2.0 KB, Downloading, 50%',
          hasTapAction: true,
        ),
      );
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(selection.selectedIds, {0});
      expect(opened, isEmpty);
      handle.dispose();
    });
  });

  group('diagnostics', () {
    testWidgets('no event carries a file name', (tester) async {
      await pump(tester, itemsOf: (id) => [_item('$id-s', spoiler: true)]);
      for (var i = 0; i < 3; i++) {
        await tap(tester, contentAt(tester, '$_last-s'));
        later();
      }
      await tester.pump(const Duration(seconds: 1));
      for (final event in diagnostics.events) {
        expect(event.toString(), isNot(contains('private-')));
      }
    });
  });
}
