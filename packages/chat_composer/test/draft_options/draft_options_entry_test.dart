/// The draft options entry: the one owner a host binds the strip to, which
/// opens the overlay or the web's menu by the policy, picks the platform's
/// form at each open by the window's width, and feeds the page and the
/// availability to whichever is up.
///
/// **Seam:** the link preview strip (`ComposerHeaderStrip`) wired to a
/// `DraftOptionsEntry` the way a host wires it (open action and hover),
/// under the composer's scopes, with a `RecordingDraftOptionsHost`, a
/// `FakeDraftBubbleBuilder`, a `ManualComposerClock` and
/// `RecordingDiagnostics` installed.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/view/composer_header_strip.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _story = LinkPreview(url: _url, title: 'A story');
final _resolved = LinkPreview(url: _url, title: 'A story', siteName: 'News');

void main() {
  late RecordingDiagnostics diagnostics;
  late RecordingDraftOptionsHost host;
  late ManualComposerClock clock;
  DraftOptionsInput? draft;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    host = RecordingDraftOptionsHost();
    clock = ManualComposerClock(DateTime(2026, 11, 28));
    draft = DraftOptionsInput(
      value: DraftLinkPart(options: LinkPreviewOptions(url: _url)),
      page: LinkPreviewState.pending,
      links: [_url],
    );
  });

  DraftOptionsEntry entryOf({DraftOptionsPolicy? policy}) {
    final entry = DraftOptionsEntry(
      policy: policy,
      host: host,
      input: () => draft,
      bubbleBuilder: FakeDraftBubbleBuilder().call,
      clock: clock,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
    );
    addTearDown(entry.dispose);
    return entry;
  }

  Future<Finder> mount(WidgetTester tester, DraftOptionsEntry entry) async {
    await tester.pumpWidget(
      composerHarness(
        Builder(
          builder: (context) => ComposerHeaderStrip(
            header: ComposerHeader.linkPreview(
              url: _url,
              page: _story,
              onOpen: (rect) => entry.open(context, rect),
              onHover: entry.hoverOf(context),
            ),
          ),
        ),
      ),
    );
    return find.byType(ComposerHeaderStrip);
  }

  void window(WidgetTester tester, double width) {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
  }

  /// Closes what is up and lets it go, past the opening's guard.
  Future<void> closeAndSettle(
    WidgetTester tester,
    DraftOptionsEntry entry,
  ) async {
    entry.session!.close(DraftOptionsCloseTrigger.outside);
    await tester.pumpAndSettle();
    clock.advance(DraftOptionsPolicy.openGuard);
  }

  List<Object?> presentations() => [
    for (final event in diagnostics.whereOp(OverlayOp.opened))
      event.fields['presentation'],
  ];

  group('the platform form', () {
    testWidgets('on iOS each open takes the form of the window it opens in: '
        'the phone, then the iPad once the window is regular width', (
      tester,
    ) async {
      window(tester, 390);
      final entry = entryOf();
      final strip = await mount(tester, entry);

      await tester.tap(strip);
      await tester.pumpAndSettle();
      expect(presentations(), ['ios']);
      await closeAndSettle(tester, entry);

      window(tester, 1024);
      await tester.pumpAndSettle();
      await tester.tap(strip);
      await tester.pumpAndSettle();

      expect(presentations(), ['ios', 'ipad']);
      expect(
        tester.widget<ChromeScrim>(find.byType(ChromeScrim)).controller.preset,
        ChromeScrimPreset.ipad,
      );
      await closeAndSettle(tester, entry);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a policy the host gives is kept at every open', (
      tester,
    ) async {
      window(tester, 1024);
      final entry = entryOf(policy: const DraftOptionsPolicy.ios());
      final strip = await mount(tester, entry);

      await tester.tap(strip);
      await tester.pumpAndSettle();

      expect(presentations(), ['ios']);
      await closeAndSettle(tester, entry);
    });
  });

  group('one owner for the overlay and the menu', () {
    for (final policy in const [
      DraftOptionsPolicy.android(),
      DraftOptionsPolicy.web(),
    ]) {
      final name = policy.presentation.name;

      testWidgets('$name: the page the host feeds reaches what is up', (
        tester,
      ) async {
        final entry = entryOf(policy: policy);
        await tester.tap(await mount(tester, entry));
        await tester.pumpAndSettle();
        expect(entry.session?.page.value, LinkPreviewState.pending);

        entry.page = LinkPreviewState.loaded(_resolved);

        expect(entry.session?.page.value, LinkPreviewState.loaded(_resolved));
        await closeAndSettle(tester, entry);
      });

      testWidgets('$name: denied previews close what is up and refuse the '
          'next open', (tester) async {
        final entry = entryOf(policy: policy);
        final strip = await mount(tester, entry);
        await tester.tap(strip);
        await tester.pumpAndSettle();

        entry.linkPreviewsAllowed = false;
        await tester.pumpAndSettle();
        clock.advance(DraftOptionsPolicy.openGuard);

        expect(entry.isOpen, isFalse);
        expect(host.denials.single.options.removed, isTrue);
        await tester.tap(strip, warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(entry.isOpen, isFalse);
        expect(diagnostics.whereOp(OverlayOp.openRefused).last.fields, {
          'why': 'denied',
        });
      });
    }

    testWidgets('only the web hovers', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        composerHarness(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        entryOf(policy: const DraftOptionsPolicy.android()).hoverOf(context),
        isNull,
      );
      expect(
        entryOf(policy: const DraftOptionsPolicy.web()).hoverOf(context),
        isNotNull,
      );
    });

    testWidgets('without a draft nothing opens', (tester) async {
      draft = null;
      final entry = entryOf(policy: const DraftOptionsPolicy.android());
      await tester.tap(await mount(tester, entry));
      await tester.pumpAndSettle();

      expect(entry.isOpen, isFalse);
      expect(diagnostics.whereOp(OverlayOp.openRefused).single.fields, {
        'why': 'noDraft',
      });
    });
  });
}
