/// The draft options overlay under a screen reader and in a right-to-left
/// text: the dismiss node outside the content, the rows as labelled buttons,
/// the polite announcements of a pending link, and the mirrored rows.
///
/// **Seams:** `DraftOptionsController.open` under the composer's scopes, with
/// a `RecordingDraftOptionsHost` on a `FakeLinkPreviewResolver`, a
/// `FakeDraftBubbleBuilder` and `RecordingDiagnostics` installed;
/// `DraftLinkPagePolicy` for the right-to-left label change.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _other = Uri.parse('https://docs.example/guide');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _url));
final _page = LinkPreviewState.loaded(LinkPreview(url: _url, title: 'Story'));
final _otherPage = LinkPreview(url: _other, title: 'Guide');
final _contour = Path()..addRect(const Rect.fromLTWH(10, 20, 60, 16));

const _platforms = <(String, DraftOptionsOverlayPolicy)>[
  ('Android', DraftOptionsPolicy$Android()),
  ('iOS', DraftOptionsPolicy$IOS()),
  ('desktop', DraftOptionsPolicy$Desktop()),
];

void main() {
  late RecordingDiagnostics diagnostics;
  late FakeLinkPreviewResolver resolver;
  late RecordingDraftOptionsHost host;
  late FakeDraftBubbleBuilder bubble;
  late ManualComposerClock clock;
  final strings = ChromeStringsPresets.english.composer.draftOptions;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    resolver = FakeLinkPreviewResolver()..answer([_other], _otherPage);
    host = RecordingDraftOptionsHost(resolver: resolver);
    bubble = FakeDraftBubbleBuilder();
    clock = ManualComposerClock(DateTime(2026, 11, 28));
  });

  Future<DraftOptionsController> openOn(
    WidgetTester tester,
    DraftOptionsOverlayPolicy policy, {
    LinkPreviewState? page,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    final controller = DraftOptionsController(
      policy: policy,
      host: host,
      bubbleBuilder: bubble.call,
      clock: clock,
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
      page: page ?? _page,
      text: const model.RichText.plain('Read this and that'),
      links: [_url, _other],
    );
    await tester.pumpAndSettle();
    clock.advance(DraftOptionsPolicy.openGuard);
    return controller;
  }

  group('dismiss node', () {
    for (final (name, policy) in _platforms) {
      testWidgets('$name: the area outside the content is one button '
          'labelled from the chrome strings; its tap closes', (tester) async {
        final handle = tester.ensureSemantics();
        final controller = await openOn(tester, policy);

        final dismiss = find.bySemanticsLabel(strings.dismiss);
        expect(dismiss, findsOneWidget);
        expect(
          tester.getSemantics(dismiss),
          matchesSemantics(
            label: strings.dismiss,
            isButton: true,
            hasTapAction: true,
          ),
        );
        expect(
          tester.getRect(dismiss),
          tester.getRect(find.byType(DraftOptionsOverlay)),
        );

        tester.semantics.tap(find.semantics.byLabel(strings.dismiss));
        await tester.pumpAndSettle();

        expect(controller.isOpen, isFalse);
        expect(
          diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
          'outside',
        );
        handle.dispose();
      });
    }
  });

  group('rows', () {
    for (final (name, policy) in _platforms) {
      testWidgets('$name: each row is a button labelled with its shown '
          'label', (tester) async {
        final handle = tester.ensureSemantics();
        await openOn(tester, policy);

        final labels = [
          strings.moveUp,
          if (policy.linkPage.applyRow) strings.applyChanges,
          switch (policy.linkPage.removeLabel) {
            DraftLinkRemoveLabel.doNotPreview => strings.doNotPreview,
            DraftLinkRemoveLabel.removePreview => strings.removePreview,
          },
        ];
        for (final label in labels) {
          expect(
            tester.getSemantics(find.bySemanticsLabel(label)),
            isSemantics(
              label: label,
              isButton: true,
              isEnabled: true,
              hasTapAction: true,
            ),
            reason: label,
          );
        }
        handle.dispose();
      });
    }
  });

  group('announcements', () {
    for (final (name, policy) in [
      ('Android', const DraftOptionsPolicy$Android()),
      ('iOS', const DraftOptionsPolicy$IOS()),
    ]) {
      testWidgets('$name: opened on a pending page, "loading preview" is '
          'announced politely, and again once it loads', (tester) async {
        final controller = await openOn(
          tester,
          policy,
          page: LinkPreviewState.pending,
        );

        expect(tester.takeAnnouncements(), [
          isAccessibilityAnnouncement(
            strings.loadingPreview,
            assertiveness: Assertiveness.polite,
          ),
        ]);

        controller.page = _page;
        await tester.pump();

        expect(tester.takeAnnouncements(), [
          isAccessibilityAnnouncement(
            strings.previewLoaded,
            assertiveness: Assertiveness.polite,
          ),
        ]);
        expect(diagnostics.whereOp(OverlayOp.announced), [
          isChatEvent(
            level: ChatEventLevel.trace,
            category: ChatEventCategory.overlay,
            correlation: const ChatCorrelation(chatId: 'chat-1'),
            fields: {'kind': 'loadingPreview'},
          ),
          isChatEvent(
            level: ChatEventLevel.trace,
            category: ChatEventCategory.overlay,
            correlation: const ChatCorrelation(chatId: 'chat-1'),
            fields: {'kind': 'loaded'},
          ),
        ]);
      });
    }

    testWidgets('desktop: a chosen link is announced while pending and '
        'once loaded', (tester) async {
      final controller = await openOn(
        tester,
        const DraftOptionsPolicy$Desktop(),
      );
      expect(tester.takeAnnouncements(), isEmpty);

      controller.session!.tapLink('$_other', _contour);
      await tester.pump();
      expect(tester.takeAnnouncements().map((a) => a.message), [
        strings.loadingPreview,
      ]);

      resolver.completeAll();
      await tester.pump();
      expect(tester.takeAnnouncements().map((a) => a.message), [
        strings.previewLoaded,
      ]);
      expect(
        diagnostics.whereOp(OverlayOp.announced).map((e) => e.fields['kind']),
        ['loadingPreview', 'loaded'],
      );
    });

    testWidgets('a loaded page and a page that comes to nothing announce '
        'nothing', (tester) async {
      final controller = await openOn(tester, const DraftOptionsPolicy$IOS());
      expect(tester.takeAnnouncements(), isEmpty);

      controller.page = LinkPreviewState.none;
      await tester.pump();

      expect(tester.takeAnnouncements(), isEmpty);
      expect(diagnostics.whereOp(OverlayOp.announced), isEmpty);
    });
  });

  group('right to left', () {
    Finder rowOf(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(DraftLinkRowView),
    );
    Rect iconOf(WidgetTester tester, String label) => tester.getRect(
      find
          .descendant(
            of: rowOf(label),
            matching: find.byWidgetPredicate(
              (w) => w is AnimatedChromeIcon || w is ChromeIcon,
            ),
          )
          .first,
    );

    for (final (name, policy, iconRight, labelRight) in [
      // The icon 17 from the right, the label ending 59 from it.
      ('Android', const DraftOptionsPolicy$Android(), 17.0, 59.0),
      // The context row mirrored: the icon 16 from the left, the label
      // ending 16 from the right.
      ('iOS', const DraftOptionsPolicy$IOS(), null, 16.0),
      ('desktop', const DraftOptionsPolicy$Desktop(), 20.0, 60.0),
    ]) {
      testWidgets('$name mirrors its rows: the label right-aligned', (
        tester,
      ) async {
        await openOn(tester, policy, textDirection: TextDirection.rtl);

        final row = tester.getRect(rowOf(strings.moveUp));
        final icon = iconOf(tester, strings.moveUp);
        final label = tester.getRect(find.text(strings.moveUp));
        switch (iconRight) {
          case final inset?:
            expect(row.right - icon.right, inset);
            expect(icon.left, greaterThan(label.right));
          case null:
            expect(icon.left - row.left, 16);
            expect(icon.right, lessThan(label.left));
        }
        expect(row.right - label.right, labelRight);
      });
    }

    testWidgets('Android changes a row label at once, with no cross-fade', (
      tester,
    ) async {
      await openOn(
        tester,
        const DraftOptionsPolicy$Android(),
        textDirection: TextDirection.rtl,
      );

      await tester.tap(rowOf(strings.moveUp));
      await tester.pump();

      expect(host.edits.single.invertMedia, isTrue);
      expect(find.text(strings.moveUp), findsNothing);
      expect(find.text(strings.moveDown), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text(strings.moveDown),
          matching: find.byType(AnimatedSwitcher),
        ),
        findsNothing,
      );
    });

    test('the policy: no label change motion in a right-to-left text on '
        'any platform', () {
      for (final policy in [
        DraftLinkPagePolicy.android,
        DraftLinkPagePolicy.ios,
        DraftLinkPagePolicy.desktop,
        DraftLinkPagePolicy.web,
      ]) {
        expect(policy.labelChangeRtl.duration, Duration.zero);
      }
      expect(
        DraftLinkPagePolicy.android
            .copyWith(labelChangeRtl: ChromeMenuRowTiming.labelCrossFade)
            .labelChangeRtl,
        ChromeMenuRowTiming.labelCrossFade,
      );
    });
  });
}
