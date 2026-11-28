/// The link page's rows as the overlay draws them: labels from the chrome
/// strings, the row anatomy, presses per platform family, the inert size
/// row, the label cross-fade and icon morph, remove and the tap burst.
///
/// **Seam:** `DraftOptionsController.open` under the composer's scopes, with
/// a `RecordingDraftOptionsHost`, a `FakeDraftBubbleBuilder` and
/// `RecordingDiagnostics` installed.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _other = Uri.parse('https://docs.example/guide');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _url));
const _photo = ContentDescriptor(key: ContentKey.external('p'));

LinkPreviewState _page({ContentDescriptor? photo}) => LinkPreviewState.loaded(
  LinkPreview(url: _url, title: 'A story', photo: photo),
);

void main() {
  late RecordingDiagnostics diagnostics;
  late RecordingDraftOptionsHost host;
  late FakeDraftBubbleBuilder bubble;
  late ManualComposerClock clock;
  final strings = ChromeStringsPresets.english.composer.draftOptions;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    host = RecordingDraftOptionsHost();
    bubble = FakeDraftBubbleBuilder();
    clock = ManualComposerClock(DateTime(2026, 11, 28));
  });

  Future<DraftOptionsController> openOn(
    WidgetTester tester,
    DraftOptionsPolicy policy, {
    LinkPreviewState? page,
    List<Uri>? links,
    LinkPreviewDismissal? dismissal,
    model.RichText text = const model.RichText.plain('Read this'),
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    final controller = DraftOptionsController(
      policy: policy,
      host: host,
      bubbleBuilder: bubble.call,
      clock: clock,
      dismissal: dismissal,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
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
        textDirection: textDirection,
      ),
    );
    controller.open(
      context,
      value: _initial,
      page: page ?? _page(photo: _photo),
      text: text,
      links: links ?? [_url],
    );
    await tester.pumpAndSettle();
    // Past the opening's guard, so presses land on the overlay.
    clock.advance(DraftOptionsController.openGuard);
    return controller;
  }

  Finder rowOf(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byType(DraftLinkRowView),
  );

  group('rows', () {
    testWidgets('Android draws its rows with the chrome strings, in chrome '
        'text, pressing with a ripple', (tester) async {
      await openOn(tester, const DraftOptionsPolicy.android());

      for (final label in [
        strings.moveUp,
        strings.shrinkPhoto,
        strings.applyChanges,
        strings.doNotPreview,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      final inks = tester.widgetList<ChromeInk>(
        find.descendant(
          of: find.byType(DraftLinkRowView),
          matching: find.byType(ChromeInk),
        ),
      );
      expect(inks, hasLength(4));
      expect(inks.map((ink) => ink.kind).toSet(), {ChromeInkKind.ripple});
      expectChromeText(tester, within: find.byType(DraftOptionsOverlay));
    });

    testWidgets('a row is 48 tall, its icon 24 at 17, its label at 59 in '
        '16 text', (tester) async {
      await openOn(tester, const DraftOptionsPolicy.android());

      final row = tester.getRect(rowOf(strings.moveUp));
      expect(row.height, 48);
      final icon = tester.getRect(
        find.descendant(
          of: rowOf(strings.moveUp),
          matching: find.byType(AnimatedChromeIcon),
        ),
      );
      expect(icon.size, const Size.square(24));
      expect(icon.left - row.left, 17);
      final label = tester.getRect(find.text(strings.moveUp));
      expect(label.left - row.left, 59);
      expect(
        tester.widget<Text>(find.text(strings.moveUp)).style?.fontSize,
        16,
      );
      // At least 77 wider than the widest label.
      final widest =
          [
                strings.moveUp,
                strings.shrinkPhoto,
                strings.applyChanges,
                strings.doNotPreview,
              ]
              .map((l) => tester.getSize(find.text(l)).width)
              .reduce((a, b) => a > b ? a : b);
      expect(row.width, greaterThanOrEqualTo(77 + widest));
    });

    testWidgets('RTL puts the icon at the end', (tester) async {
      await openOn(
        tester,
        const DraftOptionsPolicy.android(),
        textDirection: TextDirection.rtl,
      );

      final row = tester.getRect(rowOf(strings.moveUp));
      final icon = tester.getRect(
        find.descendant(
          of: rowOf(strings.moveUp),
          matching: find.byType(AnimatedChromeIcon),
        ),
      );
      expect(row.right - icon.right, 17);
    });

    testWidgets('iOS presses with the highlight', (tester) async {
      await openOn(tester, const DraftOptionsPolicy.ios());
      expect(
        tester
            .widgetList<ChromeInk>(find.byType(ChromeInk))
            .map((ink) => ink.kind)
            .toSet(),
        contains(ChromeInkKind.highlight),
      );
    });

    testWidgets('desktop draws its rows and the link hint with two links', (
      tester,
    ) async {
      await openOn(
        tester,
        const DraftOptionsPolicy.desktop(),
        links: [_url, _other],
      );

      expect(find.text(strings.removePreview), findsOneWidget);
      expect(find.text(strings.applyChanges), findsNothing);
      expect(find.text(strings.chooseLinkHint), findsOneWidget);
      final inks = tester.widgetList<ChromeInk>(
        find.descendant(
          of: find.byType(DraftLinkRowView),
          matching: find.byType(ChromeInk),
        ),
      );
      expect(inks.map((ink) => ink.kind).toSet(), {ChromeInkKind.pointer});
    });
  });

  group('size row on Android (D22)', () {
    testWidgets('inert at 50 % without shrinkable media; a touch is '
        'ignored', (tester) async {
      await openOn(
        tester,
        const DraftOptionsPolicy.android(),
        page: _page(),
        links: [_url, _other],
      );

      final size = rowOf(strings.enlargePhoto);
      expect(
        tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.text(strings.enlargePhoto),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        0.5,
      );
      expect(
        find.descendant(of: size, matching: find.byType(ChromeInk)),
        findsNothing,
      );

      await tester.tap(size);
      await tester.pumpAndSettle();

      expect(host.edits, isEmpty);
      expect(diagnostics.whereOp(OverlayOp.rowInertTouch), hasLength(1));
    });
  });

  group('taps', () {
    testWidgets('position edits invertMedia; the label cross-fades over '
        '300 ms and the icon morphs', (tester) async {
      await openOn(tester, const DraftOptionsPolicy.android());

      await tester.tap(rowOf(strings.moveUp));
      await tester.pump();

      expect(host.edits.single.invertMedia, isTrue);
      final switcher = tester.widget<AnimatedSwitcher>(
        find
            .ancestor(
              of: find.text(strings.moveDown),
              matching: find.byType(AnimatedSwitcher),
            )
            .first,
      );
      expect(switcher.duration, const Duration(milliseconds: 300));
      expect(switcher.switchInCurve, Curves.easeOutQuint);
      // Both labels while the cross-fade runs.
      expect(find.text(strings.moveUp), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      final fading = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text(strings.moveUp),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fading.opacity.value, 0);
      await tester.pumpAndSettle();
      expect(find.text(strings.moveUp), findsNothing);

      final icon = tester.widget<AnimatedChromeIcon>(
        find.descendant(
          of: rowOf(strings.moveDown),
          matching: find.byType(AnimatedChromeIcon),
        ),
      );
      expect(icon.id, ChromeIconId.moveDown);
      final morph = tester.widget<TweenAnimationBuilder<Offset>>(
        find.descendant(
          of: rowOf(strings.moveDown),
          matching: find.byType(TweenAnimationBuilder<Offset>),
        ),
      );
      expect(morph.duration, const ChromeMotion.standard().iconMorph.duration);
    });

    testWidgets('desktop changes the label at once', (tester) async {
      await openOn(tester, const DraftOptionsPolicy.desktop());

      await tester.tap(rowOf(strings.moveUp));
      await tester.pump();

      expect(find.text(strings.moveUp), findsNothing);
      expect(find.text(strings.moveDown), findsOneWidget);
    });

    testWidgets('remove sets removed, applies the dismissal and closes', (
      tester,
    ) async {
      final dismissal = LinkPreviewDismissal(
        policy: LinkPreviewDismissalPolicy.perUrl,
      );
      final controller = await openOn(
        tester,
        const DraftOptionsPolicy.ios(),
        dismissal: dismissal,
      );

      await tester.tap(rowOf(strings.doNotPreview));
      await tester.pumpAndSettle();

      expect(host.edits.single.options.removed, isTrue);
      expect(dismissal.allows(_url), isFalse);
      expect(controller.isOpen, isFalse);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'remove',
      );
    });

    testWidgets('a burst of taps on a row applies once per tap, none while '
        'the close runs', (tester) async {
      final controller = await openOn(
        tester,
        const DraftOptionsPolicy.android(),
      );

      await tester.tap(rowOf(strings.moveUp));
      await tester.pump(const Duration(milliseconds: 40));
      clock.advance(const Duration(milliseconds: 40));
      await tester.tap(find.byType(DraftLinkRowView).first);
      await tester.pumpAndSettle();
      expect(host.edits, hasLength(1));

      clock.advance(DraftLinkPagePolicy.android.rowGuard);
      await tester.tap(rowOf(strings.applyChanges));
      await tester.pump(const Duration(milliseconds: 40));
      clock.advance(DraftLinkPagePolicy.android.rowGuard);
      await tester.tap(
        find.byType(DraftLinkRowView).first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(host.edits, hasLength(1));
      expect(controller.isOpen, isFalse);
      expect(diagnostics.whereOp(OverlayOp.closed), hasLength(1));
      // The first burst's second tap was dropped by the row guard; one while
      // the overlay closes is dropped too, or passes through the closing
      // scrim: either way nothing more applies.
      expect(diagnostics.whereOp(OverlayOp.rowDropped).first.fields, {
        'row': 'position',
        'ms': 40,
      });
    });
  });
}
