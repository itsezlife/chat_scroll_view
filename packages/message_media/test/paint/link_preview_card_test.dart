/// The link preview card in a chat list: its hits and roles, what a tap on
/// the body, the button, a description link and the photo does per
/// platform, message selection, the menu request's part, the input guard,
/// the press feedback (never on a link or the button), the appear
/// transition per platform, the semantics and the diagnostics.
///
/// **Seam:** `MessageMediaView` / `MessageMediaTransition` rows of a mounted
/// `ChatScrollView` with a `ChatSelectionController` (clock injected), over
/// a `ContentAssetScope` with a `FakeAssetProducer`; observed through the
/// host's `onLinkPreview` calls, the viewer requests, the menu requests,
/// the facade's interactions, the selected set, the press transforms, the
/// semantics tree and `RecordingDiagnostics`.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chrome_foundation/chrome_foundation.dart' show ChromeInk;
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/rendering.dart' show RenderParagraph, SemanticsAction;
import 'package:flutter/widgets.dart' as widgets show RichText;
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/testing.dart' hide RecordingDiagnostics;

import '../support/media_scopes.dart';

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

const _count = 4;
const _last = _count - 1;
const _linkText = 'read more';

LinkPreview _page({ContentDescriptor? photo, String? url}) => LinkPreview(
  url: Uri.parse(url ?? 'https://example.org/private/page'),
  siteName: 'Example',
  title: 'A private title',
  description: RichText('Some private words, $_linkText.', const [
    Entity(20, _linkText.length, EntityKind.link('https://l.test/x')),
  ]),
  photo: photo,
);

ContentDescriptor _photo() => const ContentDescriptor(
  key: ContentKey.document('doc-photo'),
  size: ContentSize(800, 600),
);

void main() {
  late FakeAssetProducer producer;
  late ContentAssetScope scope;
  late MessageMediaState state;
  late RecordingDiagnostics diagnostics;
  late List<(LinkPreviewHitPart, LinkPreview)> activated;
  late List<MediaViewerRequest> opened;
  late List<ChatMessageMenuRequest> secondaryMenus;
  late List<ChatSelectionInteraction> interactions;
  late Duration now;
  late ChatSelectionController selection;

  setUp(() {
    producer = FakeAssetProducer();
    scope = ContentAssetScope.withMedia(producer: producer);
    state = MessageMediaState();
    diagnostics = RecordingDiagnostics.install();
    activated = [];
    opened = [];
    secondaryMenus = [];
    interactions = [];
    now = Duration.zero;
    addTearDown(scope.dispose);
    addTearDown(state.dispose);
  });

  MediaLayoutInput inputOf(
    LinkPreview? page, {
    String? button,
    TextDirection direction = TextDirection.ltr,
  }) => MediaLayoutInput(
    text: MediaScopes.text,
    items: const [],
    availableWidth: 380,
    displaySize: const Size(400, 600),
    captionPosition: MediaCaptionPosition.above,
    joinedBelow: true,
    reactionsBelow: true,
    correlation: const ChatCorrelation(chatId: 'chat-1', scrollId: '3'),
    linkPreview: switch (page) {
      final page? => MediaLinkPreviewInput(
        page: page,
        messageId: '$_last',
        buttonLabel: button,
        textDirection: direction,
      ),
      null => null,
    },
  );

  Future<void> pump(
    WidgetTester tester, {
    MessageMediaPolicy policy = const MessageMediaPolicy.android(),
    ChatSelectionPolicy selectionPolicy = const ChatSelectionPolicy.mobile(),
    LinkPreview? page,
    String? button,
    bool transition = false,
  }) async {
    selection = ChatSelectionController(
      policy: selectionPolicy,
      chatId: 'chat-1',
      monotonicClock: () => now,
    )..addInteractionListener(interactions.add);
    final controller = ChatScrollController()..jumpTo(_last);
    final source = _Source(_count);
    addTearDown(selection.dispose);
    addTearDown(controller.dispose);
    addTearDown(source.dispose);
    final shown = page ?? _page();
    await tester.pumpWidget(
      MediaScopes.wrap(
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
                    onSecondaryMessageTap: secondaryMenus.add,
                    messageBuilder: (context, id, message, status, runLayout) {
                      if (id != _last) return const SizedBox(height: 40);
                      final layout = policy.layout(
                        inputOf(shown, button: button),
                      );
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: MessageMediaView(
                          layout: layout,
                          items: const [],
                          policy: policy,
                          selection: selection,
                          messageId: id,
                          onOpenViewer: opened.add,
                          onLinkPreview: (part, page) =>
                              activated.add((part, page)),
                          correlation: const ChatCorrelation(
                            chatId: 'chat-1',
                            scrollId: '3',
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
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Finder cardFinder() => find.byKey(const ValueKey('linkPreviewCard'));
  Rect cardRect(WidgetTester tester) => tester.getRect(cardFinder());

  // Card coordinates of the layout's pieces, to global.
  MediaBlock$LinkPreview blockOf(MessageMediaPolicy policy, {String? button}) =>
      policy
          .layout(inputOf(_page(), button: button))
          .blocks
          .whereType<MediaBlock$LinkPreview>()
          .single;

  Offset globalOf(WidgetTester tester, LinkPreviewCard card, Offset local) =>
      cardRect(tester).topLeft + (local - card.rect.topLeft);

  Offset bodyAt(WidgetTester tester) =>
      cardRect(tester).topLeft + const Offset(14, 8);

  ChatInlineHit hitAt(Offset at) => selection.resolveInlineHit(_last, at)!;

  Future<void> tap(WidgetTester tester, Offset at, {int? buttons}) async {
    await tester.tapAt(at, buttons: buttons ?? kPrimaryButton);
    await tester.pump();
  }

  void later() => now += const Duration(seconds: 1);

  // The link's place in the description, found by its painter.
  Offset linkAt(WidgetTester tester, MessageMediaPolicy policy) {
    final card = blockOf(policy).card!;
    final piece = card.pieceOf(LinkPreviewCardPart.description)!;
    final text = find.descendant(
      of: cardFinder(),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.textSpan?.toPlainText().contains(_linkText) ?? false),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(widgets.RichText)),
    );
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 20, extentOffset: 24),
    );
    expect(boxes, isNotEmpty);
    final local = boxes.first.toRect().center;
    return globalOf(tester, card, piece.rect.topLeft + local);
  }

  double scaleUnder(WidgetTester tester, Finder of) {
    final transforms = tester.widgetList<Transform>(
      find.descendant(of: of, matching: find.byType(Transform)),
    );
    if (transforms.isEmpty) return 1;
    return transforms.first.transform.storage[0];
  }

  group('hits and roles', () {
    testWidgets('the body and the button are activate parts with their '
        'rects', (tester) async {
      await pump(tester, button: 'OPEN');
      final block = blockOf(const MessageMediaPolicy.android(), button: 'OPEN');
      final card = block.card!;

      final body = hitAt(bodyAt(tester)) as ChatInlineHit$BodyPart;
      expect(
        body.partId,
        const LinkPreviewHitPart(_last, zone: LinkPreviewZone.body),
      );
      expect(body.role, ChatBodyPartRole.activate);
      expect(body.rect, cardRect(tester));

      final buttonAt = globalOf(tester, card, card.button!.rect.center);
      final button = hitAt(buttonAt) as ChatInlineHit$BodyPart;
      expect(
        button.partId,
        const LinkPreviewHitPart(_last, zone: LinkPreviewZone.button),
      );
      expect(button.role, ChatBodyPartRole.activate);
    });

    testWidgets('a description link is an ordinary text link', (tester) async {
      await pump(tester);
      final hit = hitAt(linkAt(tester, const MessageMediaPolicy.android()));
      expect(hit, isA<ChatInlineHit$Link>());
      expect((hit as ChatInlineHit$Link).url, 'https://l.test/x');
      expect(hit.title, _linkText);

      await tap(tester, linkAt(tester, const MessageMediaPolicy.android()));
      expect(
        interactions.whereType<ChatLinkActivated>().single.url,
        'https://l.test/x',
      );
      expect(activated, isEmpty);
    });

    testWidgets('android: the photo in a card with text is an item that '
        'opens the viewer', (tester) async {
      await pump(tester, page: _page(photo: _photo()));
      final media = find.byKey(
        const ValueKey(
          MediaItemId.linkPreviewOf('$_last', slot: LinkPreviewMediaSlot.photo),
        ),
      );
      final at = tester.getRect(media).topLeft + const Offset(8, 8);
      final hit = hitAt(at) as ChatInlineHit$BodyPart;
      expect(hit.partId, isA<MediaHitPart>());
      await tap(tester, at);
      expect(opened.single.items.single, (hit.partId as MediaHitPart).itemId);
      expect(activated, isEmpty);
    });

    testWidgets('ios: the photo in a card with text opens the page', (
      tester,
    ) async {
      await pump(
        tester,
        policy: const MessageMediaPolicy.ios(),
        page: _page(photo: _photo()),
      );
      final media = find.byKey(
        const ValueKey(
          MediaItemId.linkPreviewOf('$_last', slot: LinkPreviewMediaSlot.photo),
        ),
      );
      final at = tester.getRect(media).topLeft + const Offset(8, 8);
      final hit = hitAt(at) as ChatInlineHit$BodyPart;
      expect(
        hit.partId,
        const LinkPreviewHitPart(_last, zone: LinkPreviewZone.body),
      );
      await tap(tester, at);
      expect(activated.single.$1.zone, LinkPreviewZone.body);
      expect(opened, isEmpty);
    });

    testWidgets('desktop: the photo opens the page, the enlarge button the '
        'viewer', (tester) async {
      const policy = MessageMediaPolicy.desktop();
      await pump(
        tester,
        policy: policy,
        selectionPolicy: const ChatSelectionPolicy.desktop(),
        page: LinkPreview(
          url: Uri.parse('https://example.org/p'),
          title: 'A photo page',
          type: 'photo',
          photo: _photo(),
        ),
      );
      final block = policy
          .layout(
            inputOf(
              LinkPreview(
                url: Uri.parse('https://example.org/p'),
                title: 'A photo page',
                type: 'photo',
                photo: _photo(),
              ),
            ),
          )
          .blocks
          .whereType<MediaBlock$LinkPreview>()
          .single;
      final card = block.card!;
      final photoAt = globalOf(
        tester,
        card,
        block.media!.rect.bottomLeft + const Offset(8, -8),
      );
      final photo = hitAt(photoAt) as ChatInlineHit$BodyPart;
      expect(photo.partId, isA<LinkPreviewHitPart>());
      final enlarge =
          hitAt(globalOf(tester, card, card.enlarge!.center))
              as ChatInlineHit$BodyPart;
      expect(enlarge.partId, isA<MediaHitPart>());
      await tap(tester, globalOf(tester, card, card.enlarge!.center));
      expect(opened, hasLength(1));
    });
  });

  group('normal mode', () {
    testWidgets('the body opens the page, the button runs its action; the '
        'host gets the page', (tester) async {
      await pump(tester, button: 'OPEN');
      final card = blockOf(
        const MessageMediaPolicy.android(),
        button: 'OPEN',
      ).card!;
      await tap(tester, bodyAt(tester));
      expect(activated.single.$1.zone, LinkPreviewZone.body);
      expect(
        activated.single.$2.url,
        Uri.parse('https://example.org/private/page'),
      );
      later();
      await tap(tester, globalOf(tester, card, card.button!.rect.center));
      expect(activated.last.$1.zone, LinkPreviewZone.button);
      final events = diagnostics.whereOp(MediaOp.hit);
      expect(
        [for (final e in events) e.fields['outcome']],
        [MediaHitOutcome.open, MediaHitOutcome.action],
      );
      expect([for (final e in events) e.fields['part']], ['body', 'button']);
    });

    testWidgets('a burst of taps on the body or the button acts once', (
      tester,
    ) async {
      await pump(tester, button: 'OPEN');
      final card = blockOf(
        const MessageMediaPolicy.android(),
        button: 'OPEN',
      ).card!;
      for (var i = 0; i < 4; i++) {
        await tap(tester, bodyAt(tester));
        now += const Duration(milliseconds: 50);
      }
      expect(activated, hasLength(1));
      later();
      for (var i = 0; i < 3; i++) {
        await tap(tester, globalOf(tester, card, card.button!.rect.center));
        now += const Duration(milliseconds: 50);
      }
      expect(activated, hasLength(2));
      final dropped = diagnostics.whereOp(MediaOp.activationDropped);
      expect(dropped, hasLength(5));
      expect(dropped.first.fields['part'], 'body');
      expect(dropped.last.fields['part'], 'button');
    });
  });

  group('selection', () {
    testWidgets('any tap on the card toggles the message and acts on '
        'nothing', (tester) async {
      await pump(
        tester,
        button: 'OPEN',
        page: _page(photo: _photo()),
      );
      selection.startSelection(0);
      await tester.pump();
      await tap(tester, bodyAt(tester));
      expect(selection.selectedIds, {0, _last});
      later();
      final card = blockOf(
        const MessageMediaPolicy.android(),
        button: 'OPEN',
      ).card!;
      await tap(
        tester,
        globalOf(tester, card, card.rect.bottomRight - const Offset(20, 10)),
      );
      expect(selection.selectedIds, {0});
      expect(activated, isEmpty);
      expect(opened, isEmpty);
    });

    testWidgets('desktop: a secondary click on the card opens the menu with '
        'the card part', (tester) async {
      await pump(
        tester,
        policy: const MessageMediaPolicy.desktop(),
        selectionPolicy: const ChatSelectionPolicy.desktop(),
      );
      await tap(tester, bodyAt(tester), buttons: kSecondaryMouseButton);
      expect(
        secondaryMenus.single.partId,
        const LinkPreviewHitPart(_last, zone: LinkPreviewZone.body),
      );
      expect(activated, isEmpty);
    });
  });

  group('press feedback', () {
    testWidgets('android: the body bounces, a link and the button do not '
        'press the card', (tester) async {
      await pump(tester, button: 'OPEN');
      final card = blockOf(
        const MessageMediaPolicy.android(),
        button: 'OPEN',
      ).card!;
      final cardInk = find
          .descendant(of: cardFinder(), matching: find.byType(ChromeInk))
          .first;

      var gesture = await tester.startGesture(bodyAt(tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(scaleUnder(tester, cardInk), closeTo(0.99, 1e-6));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleUnder(tester, cardInk), closeTo(1, 1e-6));

      gesture = await tester.startGesture(
        linkAt(tester, const MessageMediaPolicy.android()),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(scaleUnder(tester, cardInk), 1);
      await gesture.up();
      await tester.pumpAndSettle();

      later();
      gesture = await tester.startGesture(
        globalOf(tester, card, card.button!.rect.center),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final transforms = tester
          .widgetList<Transform>(
            find.descendant(of: cardInk, matching: find.byType(Transform)),
          )
          .map((t) => t.transform.storage[0])
          .toList();
      // The card's own scale stays; the button's goes to 0.98.
      expect(transforms.first, 1);
      expect(transforms, contains(closeTo(0.98, 1e-6)));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('no press in message selection', (tester) async {
      await pump(tester);
      selection.startSelection(0);
      await tester.pump();
      final cardInk = find
          .descendant(of: cardFinder(), matching: find.byType(ChromeInk))
          .first;
      final gesture = await tester.startGesture(bodyAt(tester));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(scaleUnder(tester, cardInk), 1);
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('appear', () {
    Future<void> pumpTransition(
      WidgetTester tester,
      MessageMediaPolicy policy,
      LinkPreview? page,
    ) => tester.pumpWidget(
      MediaScopes.wrap(
        MaterialApp(
          home: ContentAssetProvider(
            scope: scope,
            child: Align(
              alignment: Alignment.topLeft,
              child: MessageMediaTransition(
                layout: policy.layout(inputOf(page)),
                items: const [],
                policy: policy,
              ),
            ),
          ),
        ),
      ),
    );

    double cardOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .descendant(of: cardFinder(), matching: find.byType(Opacity))
              .first,
        )
        .opacity;

    testWidgets('android: the card shows at once', (tester) async {
      const policy = MessageMediaPolicy.android();
      await pumpTransition(tester, policy, null);
      await pumpTransition(tester, policy, _page());
      expect(cardOpacity(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('ios: the card fades in over 250 ms', (tester) async {
      const policy = MessageMediaPolicy.ios();
      await pumpTransition(tester, policy, null);
      await pumpTransition(tester, policy, _page());
      await tester.pump();
      expect(cardOpacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 125));
      expect(cardOpacity(tester), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(cardOpacity(tester), 1);
    });

    testWidgets('desktop: the card shows at once', (tester) async {
      const policy = MessageMediaPolicy.desktop();
      await pumpTransition(tester, policy, null);
      await pumpTransition(tester, policy, _page());
      expect(cardOpacity(tester), 1);
    });
  });

  group('semantics and diagnostics', () {
    testWidgets('one node reads "Page preview, title, text"; the button is '
        'its own node', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, button: 'OPEN');
      expect(
        find.bySemanticsLabel(
          'Page preview, A private title, Some private words, read more.',
        ),
        findsOneWidget,
      );
      final button = tester.getSemantics(find.bySemanticsLabel('OPEN'));
      expect(button.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('cardShown names the size, the width rule and the appear '
        'form, never the page', (tester) async {
      await pump(tester, page: _page(photo: _photo()));
      final shown = diagnostics.whereOp(LinkPreviewCardOp.cardShown).single;
      expect(shown.category, ChatEventCategory.linkPreview);
      expect(shown.level, ChatEventLevel.debug);
      expect(shown.fields, {
        'size': 'large',
        'widthRule': 'fillBudget',
        'appear': 'jump',
      });
      expect(shown.correlation.scrollId, '3');
      await tap(tester, bodyAt(tester));
      for (final event in diagnostics.events) {
        final text = '${event.fields}';
        expect(text, isNot(contains('example.org')));
        expect(text, isNot(contains('private')));
      }
    });
  });

  group('the time under a last card', () {
    for (final (name, policy) in const [
      ('android', MessageMediaPolicy.android()),
      ('ios', MessageMediaPolicy.ios()),
      ('desktop', MessageMediaPolicy.desktop()),
    ]) {
      testWidgets('$name: the bubble lays the host\'s time in the card\'s '
          'time slot', (tester) async {
        const composition = MediaBubbleComposition(hasCaption: true);
        final input = composition.inputFor(
          MediaLayoutInput(
            text: MediaScopes.text,
            items: const [],
            availableWidth: 380,
            displaySize: const Size(400, 600),
            chrome: const MediaLayoutChrome(timeWidth: 30, timeHeight: 14),
            linkPreview: MediaLinkPreviewInput(page: _page(), messageId: '1'),
          ),
        );
        expect(input.cardIsLast, isTrue);
        final layout = policy.layout(input);
        expect(MediaBubbleTime.of(layout, input), MediaBubbleTime.underCard);
        final slot = layout.blocks
            .whereType<MediaBlock$LinkPreview>()
            .single
            .card!
            .timeSlot!;
        const timeKey = ValueKey('time');
        await tester.pumpWidget(
          MediaScopes.wrap(
            MaterialApp(
              home: Align(
                alignment: Alignment.topLeft,
                child: MessageMediaBubbleLayout(
                  layout: layout,
                  items: const [],
                  policy: policy,
                  composition: composition,
                  caption: const SizedBox(
                    key: ValueKey('caption'),
                    width: 100,
                    height: 20,
                  ),
                  time: const SizedBox(key: timeKey),
                ),
              ),
            ),
          ),
        );
        final time = tester.getRect(find.byKey(timeKey));
        final media = tester.getRect(find.byType(MessageMediaView));
        expect(time.size, slot.size);
        expect(time.topLeft, media.topLeft + slot.topLeft);
        // The card's own top inset is its gap from the text: the caption
        // keeps no bottom padding above it.
        final caption = tester.getRect(find.byKey(const ValueKey('caption')));
        expect(media.top, caption.bottom);
      });
    }
  });

  group('rtl', () {
    testWidgets('the bar sits on the leading edge', (tester) async {
      const policy = MessageMediaPolicy.desktop();
      final layout = policy.layout(
        inputOf(_page(), direction: TextDirection.rtl),
      );
      await tester.pumpWidget(
        MediaScopes.wrap(
          Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.topLeft,
              child: MessageMediaView(
                layout: layout,
                items: const [],
                policy: policy,
              ),
            ),
          ),
        ),
      );
      final block = layout.blocks.whereType<MediaBlock$LinkPreview>().single;
      expect(block.card!.rtl, isTrue);
      expect(cardFinder(), findsOneWidget);
    });
  });

  group('no message id', () {
    testWidgets('a card of no message is no part: its node has no tap and '
        'the host hears nothing', (tester) async {
      final handle = tester.ensureSemantics();
      const policy = MessageMediaPolicy.android();
      await tester.pumpWidget(
        MediaScopes.wrap(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: MessageMediaView(
                layout: policy.layout(inputOf(_page(), button: 'OPEN')),
                items: const [],
                policy: policy,
                onLinkPreview: (part, page) => activated.add((part, page)),
              ),
            ),
          ),
        ),
      );
      for (final label in [
        'Page preview, A private title, Some private words, read more.',
        'OPEN',
      ]) {
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      }
      expect(activated, isEmpty);
      handle.dispose();
    });
  });
}
