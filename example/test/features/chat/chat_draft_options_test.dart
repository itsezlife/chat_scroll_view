/// The draft options wired into the chat: the link preview strip opens the
/// overlay (the web's menu) on the composer's draft, its edits reach the
/// draft through the link preview watcher, another link is looked up through
/// the chat's resolver, denied previews close it, and the keyboard is held
/// under it per platform.
///
/// **Seam:** the chat's input set and bottom chrome under the app's scopes
/// (`InputRig`), over a `FakeLinkPreviewResolver`, with the draft options
/// policy given and the fake preview bubble.
library;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_draft_options.dart';
import 'package:chat_scroll_view_example/src/features/logs/data/diagnostics_journal.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart' show MessageMediaPolicy;

import '../../support/fake_soft_keyboard.dart';
import '../../support/input_harness.dart';
import '../../support/test_services.dart';

final _a = Uri.parse('https://a.example/one');
final _b = Uri.parse('https://b.example/two');

final _pageA = LinkPreview(
  url: _a,
  siteName: 'Site A',
  title: 'Page one',
  type: 'article',
  photo: const ContentDescriptor(key: ContentKey.external('a-photo')),
);

final _pageB = LinkPreview(url: _b, siteName: 'Site B', title: 'Page two');

Future<InputRig> _pumpRig(
  WidgetTester tester, {
  required FakeLinkPreviewResolver resolver,
  DraftOptionsPolicy policy = const DraftOptionsPolicy.android(),
  FakeDraftBubbleBuilder? bubble,
  bool noBubble = false,
  FakeChatCapabilitiesSource? capabilities,
  FakeSoftKeyboard? keyboard,
}) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return InputRig.pump(
    tester,
    services: services,
    linkPreviewResolver: resolver,
    capabilities: capabilities,
    keyboard: keyboard,
    draftOptionsPolicy: policy,
    draftBubble: noBubble ? null : (bubble ?? FakeDraftBubbleBuilder()).call,
  );
}

/// Types [text], answers the lookups and lets the strip settle.
Future<void> _typeAndAnswer(
  WidgetTester tester,
  InputRig rig,
  FakeLinkPreviewResolver resolver,
  String text,
) async {
  await rig.typeInField(tester, text);
  resolver.completeAll();
  await rig.settle(tester);
}

Finder get _strip => find.text('Site A');

Finder get _overlay => find.byType(DraftOptionsOverlay);

DraftOptionsStrings _strings(WidgetTester tester) =>
    ChromeStringsScope.of(tester.element(_overlay)).composer.draftOptions;

Future<void> _openFromStrip(WidgetTester tester) async {
  await tester.tap(_strip);
  await tester.pump();
  await tester.pump();
}

/// Lets the overlay's guard pass and its motion run.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Takes what is still up away before the rig's tree goes: the screen
/// would dispose it while its overlay is being torn down too.
Future<void> _closeAtOnce(WidgetTester tester, InputRig rig) async {
  rig.set.draftOptions.dispose();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late FakeLinkPreviewResolver resolver;

  setUp(() {
    resolver = FakeLinkPreviewResolver()
      ..answer([_a], _pageA)
      ..answer([_b], _pageB)
      ..answer([_a, _b], _pageA);
  });

  group('opening', () {
    testWidgets('a tap on the strip opens the overlay on the draft', (
      tester,
    ) async {
      final bubble = FakeDraftBubbleBuilder();
      final rig = await _pumpRig(tester, resolver: resolver, bubble: bubble);
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');

      await _openFromStrip(tester);

      expect(_overlay, findsOneWidget);
      final preview = bubble.previews.last;
      expect(preview.part.options.url, _a);
      expect(preview.page, LinkPreviewState.loaded(_pageA));
      expect(preview.text.plain, 'see $_a ');
      expect(preview.selectable, isFalse);
      expectChromeText(tester, within: _overlay);
      await _settle(tester);
      await _closeAtOnce(tester, rig);
    });

    testWidgets('a burst of taps on the strip opens one overlay', (
      tester,
    ) async {
      final rig = await _pumpRig(tester, resolver: resolver);
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');

      await tester.tap(_strip);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_strip, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));

      expect(_overlay, findsOneWidget);
      await _settle(tester);
      expect(_overlay, findsOneWidget);
      await _closeAtOnce(tester, rig);
    });
  });

  group('edits reach the draft', () {
    testWidgets('the position row moves the card above the text', (
      tester,
    ) async {
      final rig = await _pumpRig(tester, resolver: resolver);
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');
      await _openFromStrip(tester);
      await _settle(tester);

      await tester.tap(find.text(_strings(tester).moveUp));
      await tester.pump();

      expect(rig.set.linkPreview.invertMedia, isTrue);
      expect(rig.set.linkPreview.draft.invertMedia, isTrue);
      expect(_overlay, findsOneWidget, reason: 'live apply keeps it open');
      await _settle(tester);
      await _closeAtOnce(tester, rig);
    });

    testWidgets('the size row switches the media through the size rule', (
      tester,
    ) async {
      final rig = await _pumpRig(tester, resolver: resolver);
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');
      await _openFromStrip(tester);
      await _settle(tester);

      // An article with a photo shows it small on Android.
      await tester.tap(find.text(_strings(tester).enlargePhoto));
      await tester.pump();

      expect(
        rig.set.linkPreview.card.value?.options.media,
        LinkPreviewMedia.large,
      );
      expect(rig.set.linkPreview.draft.options?.media, LinkPreviewMedia.large);
      await _settle(tester);
      await _closeAtOnce(tester, rig);
    });

    testWidgets('remove applies the dismissal: the strip goes', (tester) async {
      final rig = await _pumpRig(tester, resolver: resolver);
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');
      await _openFromStrip(tester);
      await _settle(tester);

      await tester.tap(find.text(_strings(tester).doNotPreview));
      await _settle(tester);

      expect(_overlay, findsNothing);
      expect(rig.set.linkPreview.card.value, isNull);
      expect(_strip, findsNothing);
      expect(rig.set.linkPreview.draft.dismissal, isNotNull);
      expect(rig.set.linkPreview.outgoing?.options.removed, isTrue);
    });
  });

  group('choosing another link', () {
    testWidgets('a link tap re-asks the resolver and marks the link', (
      tester,
    ) async {
      final bubble = FakeDraftBubbleBuilder();
      final rig = await _pumpRig(tester, resolver: resolver, bubble: bubble);
      await _typeAndAnswer(tester, rig, resolver, 'see $_a and $_b ');
      await _openFromStrip(tester);
      await _settle(tester);

      bubble.previews.last.onLinkTap(
        '$_b',
        Path()..addRect(const Rect.fromLTWH(10, 10, 60, 18)),
      );
      await tester.pump();

      expect(resolver.calls.last, [_b]);
      expect(find.byKey(DraftOptionsOverlay.linkHighlightKey), findsOneWidget);

      resolver.completeAll();
      await tester.pump();

      expect(bubble.previews.last.page, LinkPreviewState.loaded(_pageB));
      expect(rig.set.linkPreview.card.value?.url, _b, reason: 'live apply');
      await _settle(tester);
      await _closeAtOnce(tester, rig);
    });

    testWidgets('on desktop the choice waits for Save; Cancel keeps the link', (
      tester,
    ) async {
      final rig = await _pumpRig(
        tester,
        resolver: resolver,
        policy: const DraftOptionsPolicy.desktop(),
      );
      await _typeAndAnswer(tester, rig, resolver, 'see $_a and $_b ');
      await _openFromStrip(tester);
      await _settle(tester);

      rig.set.draftOptions.session!.tapLink('$_b', Path());
      await tester.pump();
      resolver.completeAll();
      await tester.pump();
      expect(resolver.calls.last, [_b]);
      expect(rig.set.linkPreview.card.value?.url, _a);

      await tester.tap(find.text(_strings(tester).cancel));
      await _settle(tester);

      expect(rig.set.linkPreview.card.value?.url, _a);
    });
  });

  group('denied link previews', () {
    testWidgets('close the overlay with its motion, then remove the preview', (
      tester,
    ) async {
      final diagnostics = RecordingDiagnostics.install();
      final rights = FakeChatCapabilitiesSource();
      addTearDown(rights.dispose);
      final rig = await _pumpRig(
        tester,
        resolver: resolver,
        capabilities: rights,
      );
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');
      await _openFromStrip(tester);
      await _settle(tester);

      rights.set(
        const ChatCapabilities(
          sending: SendingCapabilities(
            linkPreviews: Capability.denied(DenialReason.everyone()),
          ),
        ),
      );
      await tester.pump();
      expect(_overlay, findsOneWidget, reason: 'the close runs its motion');

      await _settle(tester);

      expect(_overlay, findsNothing);
      expect(_strip, findsNothing);
      expect(diagnostics.whereOp(OverlayOp.closed), [
        isChatEvent(fields: containsPair('trigger', 'denied')),
      ]);
      expect(diagnostics.whereOp(OverlayOp.editReported).last.fields, {
        'field': 'remove',
        'mode': 'live',
      });
      expect(rig.set.linkPreview.outgoing?.options.removed, isTrue);
    });

    testWidgets('are the chat\'s, not a remove: no dismissal follows', (
      tester,
    ) async {
      final rights = FakeChatCapabilitiesSource();
      addTearDown(rights.dispose);
      final rig = await _pumpRig(
        tester,
        resolver: resolver,
        capabilities: rights,
      );
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');
      await _openFromStrip(tester);
      await _settle(tester);
      var draftWrites = 0;
      void count() => draftWrites++;
      rig.set.linkPreview.draftChanged.addListener(count);
      addTearDown(() => rig.set.linkPreview.draftChanged.removeListener(count));

      rights.set(
        const ChatCapabilities(
          sending: SendingCapabilities(
            linkPreviews: Capability.denied(DenialReason.everyone()),
          ),
        ),
      );
      await tester.pump();
      await _settle(tester);

      expect(_overlay, findsNothing);
      expect(rig.set.linkPreview.outgoing?.options.removed, isTrue);
      expect(rig.set.linkPreview.draft.dismissal, isNull);
      expect(draftWrites, 1, reason: 'the availability, and no dismissal');
    });
  });

  group('keyboard', () {
    testWidgets('Android holds a raised keyboard and reopens it on close', (
      tester,
    ) async {
      final keyboard = FakeSoftKeyboard();
      final rig = await _pumpRig(
        tester,
        resolver: resolver,
        keyboard: keyboard,
      );
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      final hides = keyboard.hideCount;

      await _openFromStrip(tester);

      expect(
        rig.set.composer.keyboardIntent.value,
        ComposerKeyboardIntent.hold,
      );
      expect(keyboard.hideCount, hides + 1);
      expect(
        rig.set.composer.softKeyboard.value,
        isNot(SoftKeyboardMode.suppressed),
        reason: 'a suppressed field would not reopen',
      );
      await _settle(tester);

      final reopens = <void>[];
      rig.set.composer.keyboardRequests.addListener(() => reopens.add(null));
      await tester.tap(find.text(_strings(tester).applyChanges));
      await _settle(tester);

      expect(reopens, isNotEmpty);
      expect(
        rig.set.composer.keyboardIntent.value,
        ComposerKeyboardIntent.keep,
      );
    });
  });

  group('the web', () {
    testWidgets('a tap opens the anchored menu, no overlay', (tester) async {
      final rig = await _pumpRig(
        tester,
        resolver: resolver,
        policy: const DraftOptionsPolicy.web(),
      );
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');

      await _openFromStrip(tester);

      expect(find.byKey(DraftOptionsWebMenuController.menuKey), findsOneWidget);
      expect(_overlay, findsNothing);
      expectChromeText(
        tester,
        within: find.byKey(DraftOptionsWebMenuController.menuKey),
      );
      await _settle(tester);
      await _closeAtOnce(tester, rig);
    });

    testWidgets('a mouse resting on the strip opens it', (tester) async {
      final rig = await _pumpRig(
        tester,
        resolver: resolver,
        policy: const DraftOptionsPolicy.web(),
      );
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);

      await mouse.moveTo(tester.getCenter(_strip));
      await tester.pump(const Duration(milliseconds: 210));
      await tester.pump();

      expect(find.byKey(DraftOptionsWebMenuController.menuKey), findsOneWidget);
      await _closeAtOnce(tester, rig);
    });
  });

  group('diagnostics', () {
    testWidgets('an open without a bubble builder reports the missing hook', (
      tester,
    ) async {
      final diagnostics = RecordingDiagnostics.install();
      final rig = await _pumpRig(tester, resolver: resolver, noBubble: true);
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');

      await _openFromStrip(tester);

      expect(_overlay, findsOneWidget, reason: 'opens on a stand-in');
      expect(diagnostics.whereOp(ChatDraftOptionsOp.wiringMissing), [
        isChatEvent(
          level: ChatEventLevel.warning,
          category: ChatEventCategory.overlay,
          fields: {'hook': 'bubbleBuilder'},
          correlation: const ChatCorrelation(chatId: 'rig-chat'),
        ),
      ]);
      expectChromeText(tester, within: _overlay);
      await _settle(tester);
      await _closeAtOnce(tester, rig);
    });

    testWidgets('a holding policy without the keyboard carried out reports '
        'the missing hook and holds nothing', (tester) async {
      final diagnostics = RecordingDiagnostics.install();
      final rig = await _pumpRig(tester, resolver: resolver);
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');
      final options = ChatDraftOptions(
        linkPreview: rig.set.linkPreview,
        composer: rig.set.composer,
        mediaPolicy: const MessageMediaPolicy.android(),
        bubbleBuilder: FakeDraftBubbleBuilder().call,
        carriesKeyboardIntent: false,
        policy: const DraftOptionsPolicy.android(),
        correlation: () => const ChatCorrelation(chatId: 'rig-chat'),
      );
      addTearDown(options.dispose);

      options.open(tester.element(_strip), tester.getRect(_strip));
      await tester.pump();

      expect(diagnostics.whereOp(ChatDraftOptionsOp.wiringMissing), [
        isChatEvent(fields: {'hook': 'keyboardIntent'}),
      ]);
      expect(diagnostics.whereOp(OverlayOp.keyboardIntent), isEmpty);
      options.dispose();
      await tester.pump(const Duration(milliseconds: 500));
      await _closeAtOnce(tester, rig);
    });

    testWidgets("the overlay's events reach the journal", (tester) async {
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);
      final previous = ChatDiagnostics.current;
      ChatDiagnostics.current = journal.chatDiagnostics;
      addTearDown(() => ChatDiagnostics.current = previous);
      final rig = await _pumpRig(tester, resolver: resolver);
      await _typeAndAnswer(tester, rig, resolver, 'see $_a ');

      await _openFromStrip(tester);
      await _settle(tester);

      expect(
        journal.records.where(
          (record) => record.category == 'overlay' && record.op == 'opened',
        ),
        hasLength(1),
      );
      await _closeAtOnce(tester, rig);
      // The journal writes its batch on a timer.
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
