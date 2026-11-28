/// The live preview and choosing another link: the bubble the host builds
/// from the draft, the link taps it reports, the chosen link's highlight and
/// spinner while its page is pending, the rule per platform and the events.
///
/// **Seams:** `DraftOptionsSession` over a `RecordingDraftOptionsHost` on a
/// `FakeLinkPreviewResolver`; `DraftOptionsController` with a
/// `FakeDraftBubbleBuilder` for the overlay's layer. `RecordingDiagnostics`
/// installed.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _first = Uri.parse('https://news.example/story?id=7');
final _second = Uri.parse('https://blog.example/post');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _first));
final _secondPage = LinkPreview(url: _second, title: 'A post');
final _contour = Path()..addRect(const Rect.fromLTWH(10, 20, 60, 16));

void main() {
  late RecordingDiagnostics diagnostics;
  late FakeLinkPreviewResolver resolver;
  late RecordingDraftOptionsHost host;
  late ManualComposerClock clock;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    resolver = FakeLinkPreviewResolver()..answer([_second], _secondPage);
    host = RecordingDraftOptionsHost(resolver: resolver);
    clock = ManualComposerClock(DateTime(2026, 11, 28));
  });

  DraftOptionsSession open(
    DraftOptionsPolicy policy, {
    List<Uri>? links,
    LinkPreviewState page = LinkPreviewState.pending,
  }) {
    final session = DraftOptionsSession(
      policy: policy,
      host: host,
      part: DraftPart.link,
      initial: _initial,
      page: page,
      links: links ?? [_first, _second],
      clock: clock,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
      onClose: (_) {},
    );
    addTearDown(session.dispose);
    return session;
  }

  group('policy', () {
    test('Android chooses only among several links; iOS, desktop and the '
        'web any link', () {
      expect(
        const DraftOptionsPolicy.android().linkChoice,
        DraftOptionsLinkChoice.severalLinks,
      );
      for (final policy in [
        const DraftOptionsPolicy.ios(),
        const DraftOptionsPolicy.ios(iPad: true),
        const DraftOptionsPolicy.desktop(),
        const DraftOptionsPolicy.web(),
      ]) {
        expect(
          policy.linkChoice,
          DraftOptionsLinkChoice.anyLink,
          reason: '$policy',
        );
      }
    });

    test('only desktop keeps the chosen link selected', () {
      expect(const DraftOptionsPolicy.desktop().keepsChosenLinkSelected, true);
      for (final policy in [
        const DraftOptionsPolicy.android(),
        const DraftOptionsPolicy.ios(),
        const DraftOptionsPolicy.web(),
      ]) {
        expect(policy.keepsChosenLinkSelected, isFalse, reason: '$policy');
      }
    });

    test('a host overrides them', () {
      const policy = DraftOptionsPolicy.android(
        linkChoice: DraftOptionsLinkChoice.anyLink,
        keepsChosenLinkSelected: true,
      );
      expect(policy.linkChoice, DraftOptionsLinkChoice.anyLink);
      expect(policy.keepsChosenLinkSelected, isTrue);
    });
  });

  group('choosing another link', () {
    test('a tap asks the host for that link, edits the url and highlights '
        'it pending', () {
      final session = open(const DraftOptionsPolicy.android())
        ..tapLink('$_second', _contour);

      expect(host.chosenLinks, [_second]);
      expect(resolver.calls, [
        [_second],
      ]);
      expect(session.value.value.options.url, _second);
      expect(host.edits.single.options.url, _second);
      expect(session.page.value, LinkPreviewState.pending);
      final highlight = session.highlight.value!;
      expect(highlight.index, 1);
      expect(highlight.contour, same(_contour));
      expect(highlight.pending, isTrue);
      expect(diagnostics.whereOp(OverlayOp.linkTapped), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.overlay,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
          fields: {'index': 1, 'count': 2},
        ),
      ]);
      expect(diagnostics.whereOp(OverlayOp.editReported).single.fields, {
        'field': 'link',
        'mode': 'live',
      });
    });

    test('loaded drops the highlight and the page follows', () {
      final session = open(const DraftOptionsPolicy.ios())
        ..tapLink('$_second', _contour);
      clock.advance(const Duration(milliseconds: 340));
      resolver.completeAll();

      expect(session.page.value, LinkPreviewState.loaded(_secondPage));
      expect(session.highlight.value, isNull);
      expect(diagnostics.whereOp(OverlayOp.linkState).map((e) => e.fields), [
        {'state': 'pending', 'ms': 0},
        {'state': 'loaded', 'ms': 340},
      ]);
    });

    test('none drops the highlight too', () {
      resolver = FakeLinkPreviewResolver();
      host = RecordingDraftOptionsHost(resolver: resolver);
      final session = open(const DraftOptionsPolicy.ios())
        ..tapLink('$_second', _contour);
      resolver.completeAll();

      expect(session.page.value, LinkPreviewState.none);
      expect(session.highlight.value, isNull);
      expect(diagnostics.whereOp(OverlayOp.linkState).last.fields, {
        'state': 'none',
        'ms': 0,
      });
    });

    test('Android ignores a tap when the text has a single link', () {
      final session = open(const DraftOptionsPolicy.android(), links: [_first])
        ..tapLink('$_first', _contour);

      expect(host.chosenLinks, isEmpty);
      expect(session.highlight.value, isNull);
      expect(diagnostics.whereOp(OverlayOp.linkTapIgnored).single.fields, {
        'why': 'singleLink',
      });
      expect(diagnostics.whereOp(OverlayOp.linkTapped), isEmpty);
    });

    test('iOS and desktop take any link, a single one too', () {
      for (final policy in const [
        DraftOptionsPolicy.ios(),
        DraftOptionsPolicy.desktop(),
      ]) {
        final only = Uri.parse('https://only.example/');
        final session = DraftOptionsSession(
          policy: policy,
          host: host,
          part: DraftPart.link,
          initial: DraftLinkPart(options: LinkPreviewOptions(url: _first)),
          page: LinkPreviewState.pending,
          links: [only],
          onClose: (_) {},
        )..tapLink('$only', _contour);
        addTearDown(session.dispose);
        expect(session.highlight.value?.pending, isTrue, reason: '$policy');
      }
      expect(host.chosenLinks, hasLength(2));
    });

    test('desktop keeps the chosen link selected once loaded', () {
      final session = open(
        const DraftOptionsPolicy.desktop(),
        page: LinkPreviewState.loaded(LinkPreview(url: _first)),
      )..tapLink('$_second', _contour);
      resolver.completeAll();

      final highlight = session.highlight.value!;
      expect(highlight.index, 1);
      expect(highlight.pending, isFalse);
    });

    test('desktop: the choice stays in the copy until save', () {
      final session = open(const DraftOptionsPolicy.desktop())
        ..tapLink('$_second', _contour);
      expect(host.edits, isEmpty);
      expect(host.chosenLinks, [_second]);

      session.apply();
      expect(host.edits.single.options.url, _second);
      expect(diagnostics.whereOp(OverlayOp.editReported).single.fields, {
        'field': 'link',
        'mode': 'onSave',
      });
    });

    test('a burst of taps on the same link asks once', () {
      final session = open(const DraftOptionsPolicy.android());
      for (var i = 0; i < 4; i++) {
        session.tapLink('$_second', _contour);
      }

      expect(host.chosenLinks, [_second]);
      expect(diagnostics.whereOp(OverlayOp.linkTapped), hasLength(1));
      expect(
        diagnostics.whereOp(OverlayOp.linkTapIgnored).map((e) => e.fields),
        everyElement({'why': 'current'}),
      );
      expect(session.highlight.value?.pending, isTrue);
    });

    test('a tap on another link while pending follows the newer one', () {
      final third = Uri.parse('https://third.example/');
      final session = open(
        const DraftOptionsPolicy.ios(),
        links: [_first, _second, third],
      )..tapLink('$_second', _contour);
      final other = Path()..addRect(const Rect.fromLTWH(0, 40, 30, 16));
      session.tapLink('$third', other);
      resolver.completeAll();

      // The second link's answer came after the third was chosen.
      expect(session.page.value, LinkPreviewState.none);
      expect(session.value.value.options.url, third);
      expect(session.highlight.value, isNull);
    });

    test('a link not in the text is ignored', () {
      final session = open(const DraftOptionsPolicy.ios())
        ..tapLink('https://elsewhere.example/', _contour);

      expect(host.chosenLinks, isEmpty);
      expect(session.highlight.value, isNull);
      expect(diagnostics.whereOp(OverlayOp.linkTapIgnored).single.fields, {
        'why': 'notInText',
      });
    });

    test('no event carries a URL', () {
      open(const DraftOptionsPolicy.ios())
        ..tapLink('$_second', _contour)
        ..tapLink('https://elsewhere.example/', _contour);
      resolver.completeAll();

      for (final event in diagnostics.events) {
        for (final value in event.fields.values) {
          expect('$value', isNot(contains('example')), reason: '${event.op}');
        }
      }
    });
  });

  group('the live preview', () {
    late FakeDraftBubbleBuilder bubble;

    setUp(() => bubble = FakeDraftBubbleBuilder());

    Future<DraftOptionsController> openOverlay(
      WidgetTester tester,
      DraftOptionsPolicy policy, {
      List<Uri>? links,
    }) async {
      final controller = DraftOptionsController(
        policy: policy,
        host: host,
        bubbleBuilder: bubble.call,
        clock: clock,
      );
      addTearDown(controller.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        composerHarness(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox(height: 40);
            },
          ),
        ),
      );
      controller.open(
        context,
        value: _initial,
        page: LinkPreviewState.pending,
        text: model.RichText.plain('$_first and $_second'),
        links: links ?? [_first, _second],
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('the builder gets the draft and the not-selectable flag', (
      tester,
    ) async {
      await openOverlay(tester, const DraftOptionsPolicy.android());

      final preview = bubble.previews.last;
      expect(preview.text.plain, '$_first and $_second');
      expect(preview.part, _initial);
      expect(preview.page, LinkPreviewState.pending);
      expect(preview.selectable, isFalse);
    });

    testWidgets('an edit rebuilds the bubble with the new part', (
      tester,
    ) async {
      final controller = await openOverlay(
        tester,
        const DraftOptionsPolicy.android(),
      );
      final above = _initial.copyWith(invertMedia: true);
      controller.session!.edit(above, field: DraftOptionsField.position);
      await tester.pump();

      expect(bubble.previews.last.part, above);
    });

    testWidgets('onLinkTap shows the highlight and a spinner until loaded', (
      tester,
    ) async {
      await openOverlay(tester, const DraftOptionsPolicy.android());
      expect(find.byKey(DraftOptionsOverlay.linkHighlightKey), findsNothing);

      bubble.previews.last.onLinkTap('$_second', _contour);
      await tester.pump();

      expect(find.byKey(DraftOptionsOverlay.linkHighlightKey), findsOneWidget);
      expect(find.byType(ChromeSpinner), findsOneWidget);
      expect(bubble.previews.last.part.options.url, _second);

      resolver.completeAll();
      await tester.pump();

      expect(find.byKey(DraftOptionsOverlay.linkHighlightKey), findsNothing);
      expect(find.byType(ChromeSpinner), findsNothing);
      expect(bubble.previews.last.page, LinkPreviewState.loaded(_secondPage));
    });

    testWidgets('desktop keeps the highlight without the spinner', (
      tester,
    ) async {
      final controller = DraftOptionsController(
        policy: const DraftOptionsPolicy.desktop(),
        host: host,
        bubbleBuilder: bubble.call,
        clock: clock,
      );
      addTearDown(controller.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        composerHarness(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox(height: 40);
            },
          ),
        ),
      );
      controller.open(
        context,
        value: _initial,
        page: LinkPreviewState.loaded(LinkPreview(url: _first)),
        links: [_first, _second],
      );
      await tester.pumpAndSettle();

      bubble.previews.last.onLinkTap('$_second', _contour);
      await tester.pump();
      resolver.completeAll();
      await tester.pump();

      expect(find.byKey(DraftOptionsOverlay.linkHighlightKey), findsOneWidget);
      expect(find.byType(ChromeSpinner), findsNothing);
    });

    testWidgets('Android ignores taps with a single link', (tester) async {
      await openOverlay(
        tester,
        const DraftOptionsPolicy.android(),
        links: [_first],
      );
      bubble.previews.last.onLinkTap('$_first', _contour);
      await tester.pump();

      expect(find.byKey(DraftOptionsOverlay.linkHighlightKey), findsNothing);
      expect(host.chosenLinks, isEmpty);
    });
  });
}
