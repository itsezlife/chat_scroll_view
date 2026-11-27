/// The link preview in the composer's header strip: a debounced reading of
/// the typed text, never an entity in it, looked up through the host's
/// resolver, dismissed under a policy, carried in the sent message.
///
/// **Seam:** the chat's input set under the app's scopes (`InputRig`), typing
/// into the field on a fake clock, over the default resolver or a
/// `FakeLinkPreviewResolver`.
library;

import 'package:chat_composer/chat_composer.dart'
    show LinkPreviewDismissalOp, LinkPreviewDismissalPolicy;
import 'package:chat_scroll_view_example/src/features/chat/input/chat_link_preview.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

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
  LinkPreviewResolver? resolver,
  LinkPreviewDismissalPolicy? policy,
}) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return InputRig.pump(
    tester,
    services: services,
    linkPreviewResolver: resolver,
    linkPreviewDismissal: policy,
  );
}

/// Types [text] one character at a time, as a keyboard does.
Future<void> _typeSlowly(WidgetTester tester, InputRig rig, String text) async {
  final typed = StringBuffer(rig.set.composer.text.text);
  for (final character in text.split('')) {
    typed.write(character);
    await rig.typeInField(tester, typed.toString());
  }
}

/// Completes the fake's pending lookups and lets the strip rebuild.
Future<void> _answer(WidgetTester tester, FakeLinkPreviewResolver fake) async {
  fake.completeAll();
  await tester.pump();
}

void main() {
  group('reading the text', () {
    testWidgets('a space after a URL shows its preview at once', (
      tester,
    ) async {
      final rig = await _pumpRig(tester);

      await rig.typeInField(tester, 'see https://a.b ');
      await tester.pump();

      expect(find.text('a.b'), findsOneWidget);
      expect(find.text('https://a.b'), findsOneWidget);
    });

    testWidgets('a URL typed without a space shows it after one second', (
      tester,
    ) async {
      final rig = await _pumpRig(tester);
      await rig.typeInField(tester, 'see ');

      await _typeSlowly(tester, rig, 'https://a.b');
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('a.b'), findsNothing);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.text('a.b'), findsOneWidget);
    });

    testWidgets('a paste, a jump of more than two characters, is at once', (
      tester,
    ) async {
      final rig = await _pumpRig(tester);

      await rig.typeInField(tester, 'https://a.b');
      await tester.pump();

      expect(find.text('a.b'), findsOneWidget);
    });

    testWidgets('goes with the last link', (tester) async {
      final rig = await _pumpRig(tester);
      await rig.typeInField(tester, 'https://a.b and https://c.d ');
      await tester.pump();
      expect(find.text('a.b'), findsOneWidget);

      await rig.typeInField(tester, 'no links ');
      await tester.pump();

      expect(find.text('a.b'), findsNothing);
    });

    testWidgets('never puts an entity in the composer text', (tester) async {
      final rig = await _pumpRig(tester);

      await rig.typeInField(tester, 'see https://a.b @name #tag ');
      await tester.pump(const Duration(seconds: 2));

      expect(rig.set.linkPreview.card.value?.url, Uri.parse('https://a.b'));
      expect(rig.set.composer.richText.entities, isEmpty);
      expect(
        rig.set.composer.richText,
        const RichText.plain('see https://a.b @name #tag '),
      );
    });

    testWidgets('goes when the message is sent', (tester) async {
      final rig = await _pumpRig(tester);
      await rig.typeInField(tester, 'https://a.b ');
      await tester.pump();

      await rig.set.submit();
      await tester.pump();

      expect(find.text('a.b'), findsNothing);
    });
  });

  group('looking up', () {
    testWidgets('every URL of the text reaches the resolver, in order', (
      tester,
    ) async {
      final fake = FakeLinkPreviewResolver();
      final rig = await _pumpRig(tester, resolver: fake);

      await rig.typeInField(tester, 'see $_b then $_a and $_b again ');

      expect(fake.calls, [
        [_b, _a],
      ]);
      expect(rig.set.linkPreview.urls, [_b, _a]);
    });

    testWidgets('pending shows the address, loaded the page', (tester) async {
      final fake = FakeLinkPreviewResolver()..answer([_a], _pageA);
      final rig = await _pumpRig(tester, resolver: fake);

      await rig.typeInField(tester, 'see $_a ');
      await tester.pump();
      expect(rig.set.linkPreview.card.value?.isPending, isTrue);
      expect(find.text('a.example'), findsOneWidget);

      await _answer(tester, fake);

      expect(rig.set.linkPreview.card.value?.page, _pageA);
      expect(find.text('Site A'), findsOneWidget);
      expect(find.text('Page one'), findsOneWidget);
    });

    testWidgets('a lookup that finds no page hides the strip', (tester) async {
      final fake = FakeLinkPreviewResolver()..answer([_a], null);
      final rig = await _pumpRig(tester, resolver: fake);
      await rig.typeInField(tester, 'see $_a ');
      await tester.pump();

      await _answer(tester, fake);

      expect(rig.set.linkPreview.card.value, isNull);
      expect(find.text('a.example'), findsNothing);
    });

    testWidgets('a text change cancels the pending lookup', (tester) async {
      final diagnostics = RecordingDiagnostics.install();
      final fake = FakeLinkPreviewResolver();
      final rig = await _pumpRig(tester, resolver: fake);
      await rig.typeInField(tester, 'see $_a ');

      await rig.typeInField(tester, 'see $_a x');

      expect(fake.cancels, [
        [_a],
      ]);
      expect(diagnostics.whereOp(ChatLinkPreviewOp.resolveCancelled), [
        isChatEvent(
          correlation: const ChatCorrelation(chatId: 'rig-chat'),
          fields: {'reason': 'textChanged'},
        ),
      ]);

      // The next reading asks again.
      await tester.pump(ChatLinkPreview.debounce);
      expect(fake.calls, hasLength(2));
    });

    testWidgets('typing after a loaded page does not ask again', (
      tester,
    ) async {
      final fake = FakeLinkPreviewResolver()..answer([_a], _pageA);
      final rig = await _pumpRig(tester, resolver: fake);
      await rig.typeInField(tester, 'see $_a ');
      await _answer(tester, fake);

      await rig.typeInField(tester, 'see $_a and more ');

      expect(fake.calls, hasLength(1));
      expect(fake.cancels, isEmpty);
      expect(rig.set.linkPreview.card.value?.page, _pageA);
    });

    testWidgets('choosing a link looks it up alone', (tester) async {
      final fake = FakeLinkPreviewResolver()
        ..answer([_a, _b], _pageA)
        ..answer([_b], _pageB);
      final rig = await _pumpRig(tester, resolver: fake);
      await rig.typeInField(tester, '$_a $_b ');
      await _answer(tester, fake);

      rig.set.linkPreview.choose(_b);
      await _answer(tester, fake);

      expect(fake.calls.last, [_b]);
      expect(rig.set.linkPreview.chosenUrl, _b);
      expect(rig.set.linkPreview.card.value?.page, _pageB);
      expect(find.text('Site B'), findsOneWidget);
    });

    testWidgets('a resolver that throws shows nothing and says so', (
      tester,
    ) async {
      final diagnostics = RecordingDiagnostics.install();
      final fake = FakeLinkPreviewResolver()..failure = Exception('down');
      final rig = await _pumpRig(tester, resolver: fake);

      await rig.typeInField(tester, 'see $_a ');
      await tester.pump();

      expect(rig.set.linkPreview.card.value, isNull);
      expect(diagnostics.whereOp(ChatLinkPreviewOp.resolveFailed), [
        isChatEvent(
          level: ChatEventLevel.warning,
          fields: {'errorType': '_Exception'},
        ),
      ]);
    });

    testWidgets('the lookup events carry hosts and counts, never text', (
      tester,
    ) async {
      final diagnostics = RecordingDiagnostics.install();
      final fake = FakeLinkPreviewResolver()..answer([_a], _pageA);
      final rig = await _pumpRig(tester, resolver: fake);

      await rig.typeInField(tester, 'secret words $_a ');
      await _answer(tester, fake);

      expect(diagnostics.whereOp(ChatLinkPreviewOp.resolveStarted), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.linkPreview,
          correlation: const ChatCorrelation(chatId: 'rig-chat'),
          fields: {
            'candidateCount': 1,
            'chosenIndex': -1,
            'chosenHost': 'a.example',
          },
        ),
      ]);
      expect(diagnostics.whereOp(ChatLinkPreviewOp.resolveLoaded), [
        isChatEvent(
          fields: allOf(
            containsPair('pageType', 'article'),
            containsPair('hasPhoto', true),
            containsPair('hasMedia', false),
            contains('durationMs'),
          ),
        ),
      ]);
      for (final event in diagnostics.whereCategory(
        ChatEventCategory.linkPreview,
      )) {
        for (final value in event.fields.values) {
          expect('$value', isNot(contains('secret')));
          expect('$value', isNot(contains('/one')));
          expect('$value', isNot(contains('Page one')));
        }
      }
    });
  });

  group('dismissal', () {
    testWidgets('fieldUntilBigEdit: off for the field until a big edit', (
      tester,
    ) async {
      final fake = FakeLinkPreviewResolver();
      final rig = await _pumpRig(
        tester,
        resolver: fake,
        policy: LinkPreviewDismissalPolicy.fieldUntilBigEdit,
      );
      await rig.typeInField(tester, '$_a $_b ');

      rig.set.linkPreview.dismiss();
      await tester.pump();
      expect(find.text('a.example'), findsNothing);
      expect(fake.cancels, [
        [_a, _b],
      ]);

      // One character typed: still off.
      await rig.typeInField(tester, '$_a $_b x');
      await tester.pump(ChatLinkPreview.debounce);
      expect(fake.calls, hasLength(1));

      // A paste: search is on again.
      await rig.typeInField(tester, '$_a $_b xmore ');
      expect(fake.calls, hasLength(2));
    });

    testWidgets('perUrl: the next link previews', (tester) async {
      final fake = FakeLinkPreviewResolver()
        ..answer([_a, _b], _pageA)
        ..answer([_b], _pageB);
      final rig = await _pumpRig(
        tester,
        resolver: fake,
        policy: LinkPreviewDismissalPolicy.perUrl,
      );
      await rig.typeInField(tester, '$_a $_b ');
      await _answer(tester, fake);

      rig.set.linkPreview.dismiss();
      await _answer(tester, fake);

      expect(fake.calls.last, [_b]);
      expect(find.text('Site B'), findsOneWidget);
      expect(rig.set.linkPreview.dismissal.disabledUrls, {_a});
    });

    testWidgets('untilNoLinks: removed until the text has no link', (
      tester,
    ) async {
      final fake = FakeLinkPreviewResolver();
      final rig = await _pumpRig(
        tester,
        resolver: fake,
        policy: LinkPreviewDismissalPolicy.untilNoLinks,
      );
      await rig.typeInField(tester, '$_a ');
      rig.set.linkPreview.dismiss();

      await rig.typeInField(tester, '$_a and a long tail ');
      expect(fake.calls, hasLength(1));

      await rig.typeInField(tester, 'no link at all ');
      await rig.typeInField(tester, 'now $_b ');
      expect(fake.calls.last, [_b]);
    });

    testWidgets('the cross reports through the dismissal', (tester) async {
      final diagnostics = RecordingDiagnostics.install();
      final rig = await _pumpRig(
        tester,
        policy: LinkPreviewDismissalPolicy.perUrl,
      );
      await rig.typeInField(tester, '$_a ');
      await tester.pump();

      rig.set.linkPreview.dismiss();

      expect(diagnostics.whereOp(LinkPreviewDismissalOp.dismissed), [
        isChatEvent(
          correlation: const ChatCorrelation(chatId: 'rig-chat'),
          fields: {'policy': 'perUrl', 'scope': 'a.example'},
        ),
      ]);
    });
  });

  group('send', () {
    testWidgets('the message carries the options and the loaded page', (
      tester,
    ) async {
      final fake = FakeLinkPreviewResolver()..answer([_a], _pageA);
      final rig = await _pumpRig(tester, resolver: fake);
      await rig.typeInField(tester, 'see $_a ');
      await _answer(tester, fake);
      rig.set.linkPreview
        ..setMedia(LinkPreviewMedia.small)
        ..invertMedia = true;

      await rig.set.submit();

      final message = rig.messages.single;
      expect(
        message.linkPreview,
        MessageLinkPreview(
          options: LinkPreviewOptions(url: _a, media: LinkPreviewMedia.small),
          page: _pageA,
        ),
      );
      expect(message.invertMedia, isTrue);
      final payload = message.toJson();
      expect(LinkPreviewWire.readLinkPreview(payload), message.linkPreview);
      expect(LinkPreviewWire.readInvertMedia(payload), isTrue);
    });

    testWidgets('a pending lookup sends the options alone, and is dropped', (
      tester,
    ) async {
      final diagnostics = RecordingDiagnostics.install();
      final fake = FakeLinkPreviewResolver();
      final rig = await _pumpRig(tester, resolver: fake);
      await rig.typeInField(tester, 'see $_a ');

      await rig.set.submit();

      expect(
        rig.messages.single.linkPreview,
        MessageLinkPreview(options: LinkPreviewOptions(url: _a)),
      );
      expect(
        diagnostics
            .whereOp(ChatLinkPreviewOp.resolveCancelled)
            .map((event) => event.fields['reason']),
        ['sent'],
      );
    });

    testWidgets('a dismissed preview is sent removed', (tester) async {
      final rig = await _pumpRig(
        tester,
        policy: LinkPreviewDismissalPolicy.fieldUntilBigEdit,
      );
      await rig.typeInField(tester, 'see $_a ');
      await tester.pump();
      rig.set.linkPreview.dismiss();

      await rig.set.submit();

      expect(
        rig.messages.single.linkPreview?.options,
        LinkPreviewOptions(url: _a, removed: true),
      );
    });

    testWidgets('a text without links sends no preview', (tester) async {
      final rig = await _pumpRig(tester);
      await rig.typeInField(tester, 'just words ');

      await rig.set.submit();

      expect(rig.messages.single.linkPreview, isNull);
      expect(rig.messages.single.toJson(), {'body': 'just words'});
    });

    testWidgets('a send ends the dismissal', (tester) async {
      final fake = FakeLinkPreviewResolver();
      final rig = await _pumpRig(
        tester,
        resolver: fake,
        policy: LinkPreviewDismissalPolicy.perUrl,
      );
      await rig.typeInField(tester, '$_a ');
      rig.set.linkPreview.dismiss();
      await rig.set.submit();
      await tester.pump();

      await rig.typeInField(tester, '$_a ');

      expect(fake.calls.last, [_a]);
    });
  });

  group('availability', () {
    testWidgets('denied drops the page and sends removed; allowed resumes', (
      tester,
    ) async {
      final diagnostics = RecordingDiagnostics.install();
      final fake = FakeLinkPreviewResolver();
      final rig = await _pumpRig(tester, resolver: fake);
      await rig.typeInField(tester, 'see $_a ');

      rig.set.linkPreview.available = false;
      await tester.pump();
      expect(find.text('a.example'), findsNothing);
      expect(
        diagnostics
            .whereOp(ChatLinkPreviewOp.resolveCancelled)
            .map((event) => event.fields['reason']),
        ['denied'],
      );

      await rig.typeInField(tester, 'see $_a and $_b ');
      expect(fake.calls, hasLength(1));
      expect(
        rig.set.linkPreview.outgoing?.options,
        LinkPreviewOptions(url: _a, removed: true),
      );

      rig.set.linkPreview.available = true;
      expect(fake.calls.last, [_a, _b]);
    });
  });
}
