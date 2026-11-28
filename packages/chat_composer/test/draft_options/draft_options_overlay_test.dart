/// The draft options overlay over its scrim: opening from the strip, the
/// opening rules per platform, the input guard, the close paths, the denied
/// close and the events.
///
/// **Seam:** `DraftOptionsController` opened from a `ComposerHeaderStrip`'s
/// open action (or directly), under the composer's scopes, with a
/// `RecordingDraftOptionsHost`, a `FakeDraftBubbleBuilder` and
/// `RecordingDiagnostics` installed.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/view/composer_header_strip.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _url));
final _loaded = LinkPreviewState.loaded(
  LinkPreview(url: _url, siteName: 'Example News', title: 'A story'),
);

void main() {
  late RecordingDiagnostics diagnostics;
  late RecordingDraftOptionsHost host;
  late FakeDraftBubbleBuilder bubble;
  late ManualComposerClock clock;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    host = RecordingDraftOptionsHost();
    bubble = FakeDraftBubbleBuilder();
    clock = ManualComposerClock(DateTime(2026, 11, 28));
  });

  DraftOptionsController controllerOf(DraftOptionsPolicy policy) {
    final controller = DraftOptionsController(
      policy: policy,
      host: host,
      bubbleBuilder: bubble.call,
      clock: clock,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// Mounts a link preview strip whose open action opens [controller] on
  /// [page]; returns the strip's finder.
  Future<Finder> mountStrip(
    WidgetTester tester,
    DraftOptionsController controller, {
    LinkPreviewState page = LinkPreviewState.pending,
  }) async {
    await tester.pumpWidget(
      composerHarness(
        Builder(
          builder: (context) => ComposerHeaderStrip(
            header: ComposerHeader.linkPreview(
              url: _url,
              page: switch (page) {
                LinkPreviewState$Loaded(:final page) => page,
                _ => null,
              },
              onOpen: (rect) => controller.open(
                context,
                value: _initial,
                page: page,
                stripRect: rect,
              ),
            ),
          ),
        ),
      ),
    );
    return find.byType(ComposerHeaderStrip);
  }

  group('opening', () {
    testWidgets('a tap on the strip opens the overlay at the link page over '
        'a scrim with the platform preset', (tester) async {
      final controller = controllerOf(const DraftOptionsPolicy.android());
      final strip = await mountStrip(tester, controller);

      await tester.tap(strip);
      await tester.pumpAndSettle();

      expect(find.byType(DraftOptionsOverlay), findsOneWidget);
      expect(find.byType(ChromeScrim), findsOneWidget);
      expect(find.byKey(FakeDraftBubbleBuilder.bubbleKey), findsOneWidget);
      expect(controller.session?.part, DraftPart.link);
      expect(controller.session?.origin, tester.getRect(strip));
      expect(
        tester.widget<ChromeScrim>(find.byType(ChromeScrim)).controller.preset,
        ChromeScrimPreset.android,
      );
      expectChromeText(tester, within: find.byType(DraftOptionsOverlay));
    });

    testWidgets('mobile opens on a pending page, the preview loading', (
      tester,
    ) async {
      final controller = controllerOf(const DraftOptionsPolicy.ios());
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      expect(controller.isOpen, isTrue);
      expect(bubble.previews.last.page, LinkPreviewState.pending);
      expect(diagnostics.whereOp(OverlayOp.opened).single.fields, {
        'presentation': 'ios',
        'part': 'link',
        'page': 'pending',
        'apply': 'liveApply',
        'keyboardWasUp': false,
      });
    });

    testWidgets('desktop refuses a pending page', (tester) async {
      final controller = controllerOf(const DraftOptionsPolicy.desktop());
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      expect(controller.isOpen, isFalse);
      expect(find.byType(DraftOptionsOverlay), findsNothing);
      expect(diagnostics.whereOp(OverlayOp.openRefused), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.overlay,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
          fields: {'why': 'desktopNotLoaded'},
        ),
      ]);
    });

    testWidgets('desktop opens on a loaded page', (tester) async {
      final controller = controllerOf(const DraftOptionsPolicy.desktop());
      await tester.tap(await mountStrip(tester, controller, page: _loaded));
      await tester.pumpAndSettle();

      expect(controller.isOpen, isTrue);
      expect(bubble.previews.last.page, _loaded);
    });

    testWidgets('a page that moves while the overlay is up reaches the '
        'preview', (tester) async {
      final controller = controllerOf(const DraftOptionsPolicy.android());
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      controller.page = _loaded;
      await tester.pump();

      expect(bubble.previews.last.page, _loaded);
    });
  });

  group('input guard', () {
    testWidgets('a burst of taps on the strip opens one overlay', (
      tester,
    ) async {
      final controller = controllerOf(const DraftOptionsPolicy.android());
      final strip = await mountStrip(tester, controller);

      await tester.tap(strip);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(strip, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(strip, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(DraftOptionsOverlay), findsOneWidget);
      expect(controller.session?.isClosing, isFalse);
      expect(diagnostics.whereOp(OverlayOp.opened), hasLength(1));
      expect(diagnostics.whereOp(OverlayOp.closed), isEmpty);
    });

    testWidgets('opens within the guard of the accepted one are dropped', (
      tester,
    ) async {
      final controller = controllerOf(const DraftOptionsPolicy.android());
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

      bool open() => controller.open(
        context,
        value: _initial,
        page: LinkPreviewState.pending,
      );
      expect(open(), isTrue);
      clock.advance(const Duration(milliseconds: 120));
      expect(open(), isFalse);
      await tester.pumpAndSettle();

      expect(find.byType(DraftOptionsOverlay), findsOneWidget);
      expect(diagnostics.whereOp(OverlayOp.openDropped), [
        isChatEvent(level: ChatEventLevel.debug, fields: {'ms': 120}),
      ]);

      clock.advance(const Duration(seconds: 2));
      expect(open(), isFalse);
      expect(diagnostics.whereOp(OverlayOp.openRefused).single.fields, {
        'why': 'alreadyOpen',
      });
    });
  });

  group('closing', () {
    testWidgets('a press outside closes it; liveApply edits are already '
        'reported', (tester) async {
      final controller = controllerOf(const DraftOptionsPolicy.android());
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      final larger = _initial.copyWith(
        options: _initial.options.copyWith(media: LinkPreviewMedia.large),
      );
      controller.session!.edit(larger, field: DraftOptionsField.size);
      expect(host.edits, [larger]);

      clock.advance(DraftOptionsController.openGuard);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(find.byType(DraftOptionsOverlay), findsNothing);
      expect(controller.isOpen, isFalse);
      expect(host.edits, [larger]);
      expect(diagnostics.whereOp(OverlayOp.closed).single.fields, {
        'trigger': 'outside',
        'openMs': 400,
        'edits': 1,
        'committed': true,
      });
    });

    testWidgets('a press on the page does not close it', (tester) async {
      final controller = controllerOf(const DraftOptionsPolicy.android());
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      clock.advance(DraftOptionsController.openGuard);
      await tester.tap(find.byKey(FakeDraftBubbleBuilder.bubbleKey));
      await tester.pumpAndSettle();

      expect(controller.isOpen, isTrue);
    });

    testWidgets('apply closes; the overlay can open again after', (
      tester,
    ) async {
      final controller = controllerOf(const DraftOptionsPolicy.android());
      final strip = await mountStrip(tester, controller);
      await tester.tap(strip);
      await tester.pumpAndSettle();

      controller.session!.apply();
      await tester.pumpAndSettle();
      expect(find.byType(DraftOptionsOverlay), findsNothing);

      clock.advance(const Duration(seconds: 1));
      await tester.tap(strip);
      await tester.pumpAndSettle();
      expect(find.byType(DraftOptionsOverlay), findsOneWidget);
    });

    testWidgets('commitOnSave: Escape discards the copy', (tester) async {
      final controller = controllerOf(const DraftOptionsPolicy.desktop());
      await tester.tap(await mountStrip(tester, controller, page: _loaded));
      await tester.pumpAndSettle();

      controller.session!.edit(
        _initial.copyWith(invertMedia: true),
        field: DraftOptionsField.position,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(controller.isOpen, isFalse);
      expect(host.edits, isEmpty);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'escape',
      );
    });

    testWidgets('commitOnSave: Enter saves the copy', (tester) async {
      final controller = controllerOf(const DraftOptionsPolicy.desktop());
      await tester.tap(await mountStrip(tester, controller, page: _loaded));
      await tester.pumpAndSettle();

      final above = _initial.copyWith(invertMedia: true);
      controller.session!.edit(above, field: DraftOptionsField.position);
      expect(host.edits, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.isOpen, isFalse);
      expect(host.edits, [above]);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'save',
      );
    });

    testWidgets('disposing the controller takes the overlay away at once', (
      tester,
    ) async {
      final controller = DraftOptionsController(
        policy: const DraftOptionsPolicy.android(),
        host: host,
        bubbleBuilder: bubble.call,
        clock: clock,
      );
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      controller.dispose();
      await tester.pump();

      expect(find.byType(DraftOptionsOverlay), findsNothing);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'disposed',
      );
      expect(diagnostics.whereOp(OverlayOp.scrimCancelled), hasLength(1));
    });
  });

  group('link previews denied', () {
    testWidgets('close the overlay with its animation, then set removed', (
      tester,
    ) async {
      final controller = controllerOf(const DraftOptionsPolicy.android());
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      controller.linkPreviewsAllowed = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Still fading out: nothing reported yet.
      expect(find.byType(DraftOptionsOverlay), findsOneWidget);
      expect(host.edits, isEmpty);

      await tester.pumpAndSettle();
      expect(find.byType(DraftOptionsOverlay), findsNothing);
      expect(host.edits, [
        _initial.copyWith(options: _initial.options.copyWith(removed: true)),
      ]);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'denied',
      );
    });

    testWidgets('refuse an open', (tester) async {
      final controller = controllerOf(const DraftOptionsPolicy.android())
        ..linkPreviewsAllowed = false;
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      expect(controller.isOpen, isFalse);
      expect(diagnostics.whereOp(OverlayOp.openRefused).single.fields, {
        'why': 'denied',
      });
    });
  });

  group('title', () {
    Future<void> openOn(WidgetTester tester, DraftOptionsPolicy policy) async {
      final controller = controllerOf(policy);
      await tester.tap(await mountStrip(tester, controller, page: _loaded));
      await tester.pumpAndSettle();
    }

    final strings = ChromeStringsPresets.english.composer.draftOptions;

    testWidgets('Android: title and subtitle', (tester) async {
      await openOn(tester, const DraftOptionsPolicy.android());

      expect(find.text(strings.linkTitle), findsOneWidget);
      expect(find.text(strings.linkSubtitle), findsOneWidget);
      expectChromeText(tester, within: find.byType(DraftOptionsOverlay));
    });

    testWidgets('desktop: a title with one part', (tester) async {
      await openOn(tester, const DraftOptionsPolicy.desktop());

      expect(find.text(strings.linkTitle), findsOneWidget);
      expect(find.text(strings.linkSubtitle), findsNothing);
    });

    testWidgets('iOS: none', (tester) async {
      await openOn(tester, const DraftOptionsPolicy.ios());

      expect(find.text(strings.linkTitle), findsNothing);
      expect(find.text(strings.linkSubtitle), findsNothing);
    });
  });

  group('scrim events', () {
    testWidgets('report the scrim phases with owner draftOptions', (
      tester,
    ) async {
      final controller = controllerOf(const DraftOptionsPolicy.desktop());
      await tester.tap(await mountStrip(tester, controller, page: _loaded));
      await tester.pumpAndSettle();
      clock.advance(DraftOptionsController.openGuard);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(diagnostics.whereOp(OverlayOp.scrimStillSkipped), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.overlay,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
          fields: {
            'owner': 'draftOptions',
            'preset': 'desktop',
            'why': 'presetNoBlur',
          },
        ),
      ]);
      expect(diagnostics.whereOp(OverlayOp.scrimDismissed).single.fields, {
        'owner': 'draftOptions',
        'preset': 'desktop',
        'by': 'outside',
        'closeOn': 'up',
      });
      expect(diagnostics.whereOp(OverlayOp.scrimDisposed).single.fields, {
        'owner': 'draftOptions',
        'preset': 'desktop',
        'stills': 0,
      });
    });

    testWidgets('no event carries the URL', (tester) async {
      final controller = controllerOf(const DraftOptionsPolicy.android());
      await tester.tap(await mountStrip(tester, controller, page: _loaded));
      await tester.pumpAndSettle();
      clock.advance(DraftOptionsController.openGuard);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      for (final event in diagnostics.events) {
        expect(event.fields.values.join(' '), isNot(contains('news.example')));
      }
    });
  });
}
