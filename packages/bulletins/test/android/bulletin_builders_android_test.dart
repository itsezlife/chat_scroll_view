import 'package:bulletins/bulletins.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'android_harness.dart';

void main() {
  late AndroidHarness h;

  tearDown(() => h.dispose());

  Future<Rect> show(
    WidgetTester tester,
    Bulletin bulletin, {
    BulletinBuilders? builders,
  }) async {
    await tester.pumpWidget(
      h.app(builders: builders ?? BulletinBuilders$Android.create()),
    );
    h.controller.show(bulletin);
    // A countdown repaints every frame and never settles: pump past the
    // enter spring instead.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return tester.getRect(find.byType(BulletinCard));
  }

  TextStyle styleOf(WidgetTester tester, String text) {
    final rich = tester.widget<RichText>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );
    // A message is a rich text whose one child span carries its style.
    final span = rich.text as TextSpan;
    return switch (span.children) {
      [TextSpan(:final style?)] => span.style!.merge(style),
      _ => span.style!,
    };
  }

  int? maxLinesOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).maxLines;

  group('frame', () {
    testWidgets('outside a chat the card is the opaque undo background', (
      tester,
    ) async {
      h = AndroidHarness();
      await show(tester, const Bulletin(message: 'Copied'));
      expect(find.byType(GlassSurface), findsNothing);
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(BulletinCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xEA272F38));
      expect(decoration.borderRadius, BorderRadius.circular(16));
    });

    testWidgets('in a chat the card is glass tinted with the undo background, '
        'with no edge stroke or shadow', (tester) async {
      h = AndroidHarness();
      await show(
        tester,
        const Bulletin(message: 'Copied'),
        builders: BulletinBuilders$Android.create(glass: true),
      );
      final glass = find.byType(GlassSurface);
      expect(glass, findsOneWidget);
      expect(tester.widget<GlassSurface>(glass).cornerRadius, 16);
      final material = tester.widget<GlassSurface>(glass).material;
      final colors = ChromeThemeScope.glassOf(
        tester.element(glass),
      ).colorsOf(material);
      expect(colors.tint, const Color(0xEA272F38));
      expect(colors.strokeTop.a, 0);
      expect(colors.strokeBottom.a, 0);
      expect(colors.shadow.a, 0);
    });

    testWidgets('the card sits 16 from the sides and 8 above the obstruction', (
      tester,
    ) async {
      h = AndroidHarness(obstruction: const EdgeInsets.only(bottom: 100));
      final card = await show(tester, const Bulletin(message: 'Copied'));
      final surface = tester.getRect(find.byType(BulletinHost));
      expect(card.left, surface.left + 16);
      expect(card.right, surface.right - 16);
      expect(card.bottom, surface.bottom - 100 - 8);
      expect(card.height, 48);
    });
  });

  group('text', () {
    testWidgets('a message alone is one 15 line, 16 from the start', (
      tester,
    ) async {
      h = AndroidHarness();
      final card = await show(tester, const Bulletin(message: 'Copied'));
      expect(styleOf(tester, 'Copied').fontSize, 15);
      expect(styleOf(tester, 'Copied').color, const Color(0xFFFFFFFF));
      expect(maxLinesOf(tester, 'Copied'), 1);
      expect(tester.getRect(find.text('Copied')).left, card.left + 16);
    });

    testWidgets('a title is 14 medium over a 13 subtitle of two lines', (
      tester,
    ) async {
      h = AndroidHarness();
      await show(
        tester,
        const Bulletin(title: 'Stickers removed', message: 'Cats'),
      );
      final title = styleOf(tester, 'Stickers removed');
      expect(title.fontSize, 14);
      expect(title.fontWeight, FontWeight.w500);
      expect(maxLinesOf(tester, 'Stickers removed'), 1);
      expect(styleOf(tester, 'Cats').fontSize, 13);
      expect(maxLinesOf(tester, 'Cats'), 2);
      expect(
        tester.getRect(find.text('Cats')).top,
        greaterThanOrEqualTo(
          tester.getRect(find.text('Stickers removed')).bottom,
        ),
      );
    });

    testWidgets('an undo message wraps to two lines', (tester) async {
      h = AndroidHarness();
      await show(
        tester,
        Bulletin(
          message: 'Stickers removed',
          action: BulletinAction.undo(onUndo: () {}),
        ),
      );
      expect(maxLinesOf(tester, 'Stickers removed'), 2);
      expect(styleOf(tester, 'Stickers removed').fontSize, 15);
      h.controller.dismiss();
    });

    testWidgets('a message beside a button is 14 and wraps to three lines', (
      tester,
    ) async {
      h = AndroidHarness();
      await show(
        tester,
        Bulletin(
          message: 'GIF saved',
          action: BulletinAction.button(label: 'View', onPressed: () {}),
        ),
      );
      expect(styleOf(tester, 'GIF saved').fontSize, 14);
      expect(maxLinesOf(tester, 'GIF saved'), 3);
    });

    testWidgets('a link is drawn in the accent and opens on tap', (
      tester,
    ) async {
      h = AndroidHarness();
      var opened = 0;
      await show(
        tester,
        Bulletin(
          message: 'Limit reached. More with Premium',
          links: [BulletinLink(start: 25, end: 32, onTap: () => opened++)],
        ),
      );
      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byType(BulletinCard),
          matching: find.byType(RichText),
        ),
      );
      final message = (rich.text as TextSpan).children!.single as TextSpan;
      final link = message.children!.last as TextSpan;
      expect(link.text, 'Premium');
      expect(link.style!.color, const Color(0xFF85CAFF));
      (link.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, 1);
    });
  });

  group('leading', () {
    testWidgets('an icon is 24, centred in the 56 slot at the card start', (
      tester,
    ) async {
      h = AndroidHarness();
      final card = await show(
        tester,
        const Bulletin(
          message: 'Copied',
          leading: BulletinLeading.icon(ChromeIconId.confirm),
        ),
      );
      final icon = tester.getRect(find.byType(ChromeIcon));
      expect(icon.size, const Size.square(24));
      expect(icon.center.dx, card.left + 28);
      expect(icon.center.dy, closeTo(card.center.dy, 0.01));
      expect(tester.getRect(find.text('Copied')).left, card.left + 56);
    });

    testWidgets('an animation plays in a 32 box centred in the 56 slot', (
      tester,
    ) async {
      h = AndroidHarness();
      final sources = <Object>[];
      final card = await show(
        tester,
        const Bulletin(
          message: 'Copied',
          leading: BulletinLeading.animation('copy'),
        ),
        builders: BulletinBuilders$Android.create(
          animation: (context, source, view) {
            sources.add(source);
            return const ColoredBox(
              key: ValueKey('lottie'),
              color: Color(0xFFFF0000),
            );
          },
        ),
      );
      expect(sources, contains('copy'));
      final box = tester.getRect(find.byKey(const ValueKey('lottie')));
      expect(box.size, const Size.square(32));
      expect(box.center.dx, card.left + 28);
      expect(tester.getRect(find.text('Copied')).left, card.left + 56);
    });

    testWidgets('a thumbnail is 29 at 12 from the start, the text at 54', (
      tester,
    ) async {
      h = AndroidHarness();
      final card = await show(
        tester,
        const Bulletin(
          title: 'Added to favourites',
          message: 'Cats',
          leading: BulletinLeading.thumbnail('sticker-1'),
        ),
        builders: BulletinBuilders$Android.create(
          thumbnail: (context, source, view) =>
              const SizedBox.expand(key: ValueKey('thumb')),
        ),
      );
      final thumb = tester.getRect(find.byKey(const ValueKey('thumb')));
      expect(thumb.size, const Size.square(29));
      expect(thumb.left, card.left + 12);
      expect(card.height, greaterThanOrEqualTo(53));
      expect(
        tester.getRect(find.text('Added to favourites')).left,
        card.left + 54,
      );
    });

    testWidgets('without a builder the animation slot keeps its size', (
      tester,
    ) async {
      h = AndroidHarness();
      final card = await show(
        tester,
        const Bulletin(
          message: 'Copied',
          leading: BulletinLeading.animation('copy'),
        ),
      );
      expect(tester.getRect(find.text('Copied')).left, card.left + 56);
    });

    testWidgets('the countdown is a 20 ring at 21 from the start, with the '
        'seconds left in white', (tester) async {
      h = AndroidHarness();
      final card = await show(
        tester,
        Bulletin(
          message: 'Stickers removed',
          leading: const BulletinLeading.countdown(),
          action: BulletinAction.undo(onUndo: () {}),
        ),
      );
      final ring = tester.getRect(find.byType(BulletinCountdown$Android));
      expect(ring.size, const Size.square(20));
      expect(ring.left, card.left + 21);
      expect(
        tester.getRect(find.text('Stickers removed')).left,
        card.left + 56,
      );
      expect(find.text('5'), findsOneWidget);
      expect(styleOf(tester, '5').fontSize, 12);
      expect(styleOf(tester, '5').color, const Color(0xFFFFFFFF));

      h.clock.advance(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 16));
      // The new digit slides in while the old one slides out.
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('5'), findsNothing);
      h.controller.dismiss();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('action', () {
    testWidgets('Undo is 14 medium accent, its text 20 from the card end', (
      tester,
    ) async {
      h = AndroidHarness();
      final card = await show(
        tester,
        Bulletin(
          message: 'Stickers removed',
          action: BulletinAction.undo(onUndo: () {}),
        ),
      );
      final undo = styleOf(tester, 'Undo');
      expect(undo.fontSize, 14);
      expect(undo.fontWeight, FontWeight.w500);
      expect(undo.color, const Color(0xFF85CAFF));
      expect(tester.getRect(find.text('Undo')).right, card.right - 20);
      expect(
        tester.getRect(find.text('Stickers removed')).right,
        lessThanOrEqualTo(tester.getRect(find.text('Undo')).left - 24),
      );
      h.controller.dismiss();
    });

    testWidgets('pressing Undo undoes', (tester) async {
      h = AndroidHarness();
      var undos = 0;
      await show(
        tester,
        Bulletin(
          message: 'Stickers removed',
          action: BulletinAction.undo(onUndo: () => undos++),
        ),
      );
      final handle = h.controller.current.value!;
      await tester.tap(find.text('Undo'));
      expect(undos, 1);
      expect(handle.exit, BulletinExit.undone);
    });

    testWidgets('the action presses with the chrome ink: the accent at 0x19 '
        'in a 6 radius', (tester) async {
      h = AndroidHarness();
      var presses = 0;
      await show(
        tester,
        Bulletin(
          message: 'GIF saved',
          action: BulletinAction.button(
            label: 'View',
            onPressed: () => presses++,
          ),
        ),
      );
      final ink = tester.widget<ChromeInk>(
        find.ancestor(of: find.text('View'), matching: find.byType(ChromeInk)),
      );
      expect(ink.color, const Color(0x1985CAFF));
      expect(ink.borderRadius, BorderRadius.circular(6));

      await tester.tap(find.text('View'));
      expect(presses, 1);
    });
  });
}
