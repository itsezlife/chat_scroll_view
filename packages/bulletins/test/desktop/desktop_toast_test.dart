import 'package:bulletins/bulletins.dart';
import 'package:bulletins/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _surface = Size(800, 600);

/// A desktop surface: the desktop policy, builders and colours over a child
/// that counts the taps reaching it.
class _Harness {
  _Harness() : clock = ManualBulletinClock() {
    controller = BulletinController(
      policy: const BulletinPolicy.desktop(),
      clock: clock,
    );
  }

  final ManualBulletinClock clock;
  late final BulletinController controller;
  int taps = 0;

  Widget app({BulletinBuilders? builders}) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: _surface),
      child: ChromeThemeScope(
        palette: const ChromePalette.dark(),
        bulletin: BulletinTokens.referenceDesktop,
        child: ChromeStringsScope(
          strings: ChromeStringsPresets.english,
          child: ChromeMotionScope(
            child: Center(
              child: SizedBox.fromSize(
                size: _surface,
                child: BulletinHost(
                  controller: controller,
                  builders: builders ?? DesktopBulletinBuilders.create(),
                  announce: (_, _) {},
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void dispose() => controller.dispose();
}

Rect _card(WidgetTester tester) => tester.getRect(find.byType(BulletinCard));

Rect _surfaceRect(WidgetTester tester) =>
    tester.getRect(find.byType(BulletinHost));

double _opacityOf(WidgetTester tester, String text) => tester
    .widget<Opacity>(
      find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  late _Harness h;

  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  group('layout', () {
    testWidgets('a short toast is 160 wide, centred', (tester) async {
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final card = _card(tester);
      final surface = _surfaceRect(tester);
      expect(card.width, 160);
      expect(card.center.dx, closeTo(surface.center.dx, 0.5));
      expect(card.center.dy, closeTo(surface.center.dy, 0.5));
    });

    testWidgets('a long toast wraps at 360', (tester) async {
      await tester.pumpWidget(h.app());
      h.controller.show(Bulletin(message: 'word ' * 40));
      await tester.pumpAndSettle();
      final card = _card(tester);
      expect(card.width, 360);
      expect(card.height, greaterThan(13 + 12 + 2 * 13));
    });

    testWidgets('a toast between the bounds takes its text width', (
      tester,
    ) async {
      await tester.pumpWidget(h.app());
      // The test font draws every glyph 13 px wide at size 13.
      const message = 'Sixteen letters!';
      h.controller.show(const Bulletin(message: message));
      await tester.pumpAndSettle();
      expect(_card(tester).width, 19 + message.length * 13 + 19);
    });

    testWidgets('an icon slot replaces the start padding', (tester) async {
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(
          message: 'Link copied',
          leading: BulletinLeading.icon(ChromeIconId.confirm),
        ),
      );
      await tester.pumpAndSettle();
      final card = _card(tester);
      final slot = tester.getRect(find.byType(BulletinLeadingSlot));
      expect(slot.left, card.left);
      expect(slot.width, 44);
      final icon = tester.getRect(find.byType(ChromeIcon));
      expect(icon.width, 20);
      expect(icon.left - card.left, 12);
      expect(icon.center.dy, closeTo(card.center.dy, 0.5));
    });

    testWidgets('the title is the bold first line of one wrapping block', (
      tester,
    ) async {
      await tester.pumpWidget(h.app());
      h.controller.show(Bulletin(title: 'Stickers', message: 'word ' * 60));
      await tester.pumpAndSettle();
      final text = tester.widget<RichText>(
        find.descendant(
          of: find.byType(BulletinMessage),
          matching: find.byType(RichText),
        ),
      );
      expect(text.maxLines, DesktopBulletinBuilders.maxLines);
      expect(text.text.toPlainText(), startsWith('Stickers\nword'));
    });

    testWidgets('an attached toast sits 13 from its edge', (tester) async {
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(message: 'Copied', placement: BulletinPlacement.bottom),
      );
      await tester.pumpAndSettle();
      expect(_card(tester).bottom, _surfaceRect(tester).bottom - 13);
    });
  });

  group('motion', () {
    testWidgets('a centred toast fades in over 200 ms, linear', (tester) async {
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_opacityOf(tester, 'Copied'), closeTo(0.5, 0.01));
      expect(handle.isEntered, isFalse);
      await tester.pump(const Duration(milliseconds: 101));
      expect(handle.isEntered, isTrue);
    });

    testWidgets('it fades out over 1000 ms after its 1.5 s', (tester) async {
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      h.clock.advance(const Duration(milliseconds: 1500));
      expect(handle.exit, BulletinExit.timedOut);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_opacityOf(tester, 'Copied'), closeTo(0.5, 0.01));
      await tester.pump(const Duration(milliseconds: 501));
      expect(find.text('Copied'), findsNothing);
    });

    testWidgets('a replaced toast fades out while the new one fades in', (
      tester,
    ) async {
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'One'));
      await tester.pumpAndSettle();
      h.controller.show(const Bulletin(message: 'Two'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_opacityOf(tester, 'One'), closeTo(0.7, 0.01));
      expect(_opacityOf(tester, 'Two'), 1);
      await tester.pumpAndSettle();
      expect(find.text('One'), findsNothing);
    });

    testWidgets('an attached toast slides 160 ms and never fades', (
      tester,
    ) async {
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(message: 'Copied', placement: BulletinPlacement.top),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final card = _card(tester);
      final surface = _surfaceRect(tester);
      // Halfway from fully above the edge to 13 below it.
      expect(card.top, closeTo(surface.top + (13 - card.height) / 2, 1));
      expect(
        find.ancestor(of: find.text('Copied'), matching: find.byType(Opacity)),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 81));
      expect(_card(tester).top, surface.top + 13);
    });
  });

  group('pointers', () {
    testWidgets('a plain toast lets a click through', (tester) async {
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      await tester.tapAt(_card(tester).center);
      expect(h.taps, 1);
    });

    testWidgets('a toast with a link catches it and runs the link', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(h.app());
      h.controller.show(
        Bulletin(
          message: 'Limit reached. More',
          links: [BulletinLink(start: 15, end: 19, onTap: () => opened++)],
        ),
      );
      await tester.pumpAndSettle();
      final card = _card(tester);
      // The link is the last four glyphs, 13 px each, before the end padding.
      await tester.tapAt(Offset(card.right - 19 - 26, card.center.dy));
      expect(opened, 1);
      expect(h.taps, 0);
    });

    testWidgets('a toast with an action catches it', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(h.app());
      h.controller.show(
        Bulletin(
          message: 'Premium sticker',
          action: BulletinAction.button(
            label: 'View',
            onPressed: () => pressed++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      expect(pressed, 1);
      expect(h.taps, 0);
    });
  });

  group('leading sources', () {
    testWidgets('the host resolves a Lottie icon at 20 px', (tester) async {
      await tester.pumpWidget(
        h.app(
          builders: DesktopBulletinBuilders.create(
            animation: (context, source, view) =>
                Text('$source', key: const ValueKey('lottie')),
          ),
        ),
      );
      h.controller.show(
        const Bulletin(
          message: 'Link copied',
          leading: BulletinLeading.animation('toast/voip_invite'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('toast/voip_invite'), findsOneWidget);
      expect(
        tester.getSize(
          find
              .ancestor(
                of: find.byKey(const ValueKey('lottie')),
                matching: find.byType(SizedBox),
              )
              .first,
        ),
        const Size.square(20),
      );
    });
  });
}
