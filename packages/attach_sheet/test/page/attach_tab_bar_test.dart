import 'dart:async';

import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pages_rig.dart';

/// A host's own tab bar: its glass and colours, on the Android bar.
final class _CustomTabs extends AttachSheetPolicy$Android {
  const _CustomTabs();

  static const glass = GlassMaterial.tabs;

  @override
  AttachTabBarStyle get tabBar => super.tabBar.copyWith(
    glass: glass.copyWith(strokeWidth: 1),
    colors: _colors,
  );
}

AttachTabColors _colors(ChromePalette palette, AttachTokens tokens) =>
    const AttachTabColors(
      selected: Color(0xFFFF0000),
      selectedLabel: Color(0xFFFF0000),
      unselected: Color(0xFF00FF00),
      indicator: Color(0x170000FF),
      pressed: Color(0x0F000000),
    );

GlassSurface _barGlass(WidgetTester tester) => tester.widget<GlassSurface>(
  find.byKey(const ValueKey('attach-tab-bar-glass')),
);

/// The opacity layers above [layer] that are not opaque.
List<OpacityLayer> _fadingAbove(Layer layer) => [
  for (Layer? l = layer.parent; l != null; l = l.parent)
    if (l is OpacityLayer && (l.alpha ?? 255) < 255) l,
];

/// The scene filters of the tab bar's glass.
Iterable<Layer> _barFilters(WidgetTester tester) => [
  for (final element
      in find
          .descendant(
            of: find.byKey(const ValueKey('attach-tab-bar')),
            matching: find.byType(BackdropFilter),
          )
          .evaluate())
    element.renderObject!.debugLayer!,
];

/// The ripple's circle as [press] last painted it.
({Offset center, double radius, Color color}) _ripple(
  WidgetTester tester,
  Finder press,
) {
  final canvas = _CircleCanvas();
  final box = tester.renderObject<RenderBox>(press);
  // The painter paints the ripple's circle once per frame.
  (box as RenderCustomPaint).painter!.paint(canvas, box.size);
  return canvas.circle!;
}

final class _CircleCanvas implements Canvas {
  ({Offset center, double radius, Color color})? circle;

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circle = (center: c, radius: radius, color: paint.color);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const android = AttachSheetPolicy.android();
  const ios = AttachSheetPolicy.ios();

  group('Android bar', () {
    testWidgets('a 56 glass pill 7 from the sides and above the bottom, the '
        'tabs 48 tall 4 inside it', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      final bar = tester.getRect(find.byKey(const ValueKey('attach-tab-bar')));
      expect(bar, const Rect.fromLTRB(7, 800 - 7 - 56, 400 - 7, 800 - 7));
      final glass = _barGlass(tester);
      expect(glass.material, GlassMaterial.tabs);
      expect(glass.cornerRadius, 28);

      final tab = tester.getRect(rig.tab('gallery'));
      expect(tab.top, bar.top + 4);
      expect(tab.left, bar.left + 4);
      expect(tab.height, 48);
      final files = tester.getRect(rig.tab('files'));
      expect(files.right, closeTo(bar.right - 4, 1));
    });

    testWidgets('a 24 icon 4 from the tab top; an 11 label from 28.33, '
        'medium, extra bold when shown', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      final tab = tester.getRect(rig.tab('files'));
      final icon = tester.getRect(
        find.byKey(const ValueKey('attach-tab-icon-files')),
      );
      expect(icon.size, const Size(24, 24));
      expect(icon.top - tab.top, 4);
      expect(icon.center.dx, closeTo(tab.center.dx, 0.01));

      Text label(String id) => tester.widget<Text>(
        find.descendant(of: rig.tab(id), matching: find.text(id)),
      );
      final labelTop = tester
          .getTopLeft(
            find.descendant(of: rig.tab('files'), matching: find.text('files')),
          )
          .dy;
      expect(labelTop - tab.top, closeTo(28.33, 0.01));
      expect(label('files').style!.fontSize, 11);
      expect(label('files').style!.fontWeight, FontWeight.w500);
      expect(label('gallery').style!.fontWeight, FontWeight.w800);
      expectChromeText(
        tester,
        within: find.byKey(const ValueKey('attach-tab-bar')),
      );
    });

    testWidgets('the shown tab in the accent, the others in the text colour', (
      tester,
    ) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      final tokens = AttachTokens.fromPalette(const ChromePalette.light());
      Color labelColor(String id) => tester
          .widget<Text>(
            find.descendant(of: rig.tab(id), matching: find.text(id)),
          )
          .style!
          .color!;
      expect(labelColor('gallery'), tokens.tabSelectedLabel);
      expect(labelColor('files'), tokens.tabUnselected);
    });

    testWidgets('a tab held down ripples from the finger, clipped to the '
        "tab's stadium, and fades once it lifts", (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      final tokens = AttachTokens.fromPalette(const ChromePalette.light());
      final press = find.byKey(const ValueKey('attach-tab-press-files'));
      final tab = tester.getRect(rig.tab('files'));
      final stadium = RRect.fromRectAndRadius(
        Offset.zero & tab.size,
        Radius.circular(tab.shortestSide / 2),
      );
      expect(press, paintsNothing);

      final down = tab.centerLeft + const Offset(12, 0);
      final gesture = await tester.startGesture(down);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 16));
      // Early: a small circle near the finger, inside the stadium.
      final start = tab.size.longestSide * 0.3;
      expect(
        press,
        paints
          ..clipRRect(rrect: stadium)
          ..circle(),
      );
      final early = _ripple(tester, press);
      expect(early.center.dx, lessThan(tab.width / 2));
      expect(early.radius, inExclusiveRange(start, tab.size.longestSide));

      await tester.pump(const Duration(milliseconds: 300));
      final held = _ripple(tester, press);
      // Grown: centred on the tab, past every corner.
      expect(held.center.dx, closeTo(tab.width / 2, 0.5));
      expect(
        held.radius,
        closeTo(Offset(tab.width, tab.height).distance / 2, 0.5),
      );
      expect(held.color.a, closeTo(tokens.tabPressed.a, 1e-6));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 75));
      expect(_ripple(tester, press).color.a, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(press, paintsNothing);
    });

    testWidgets("the shown tab's mark grows from 0.6 and fades in over "
        '320 ms as the old one shrinks away', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      final tokens = AttachTokens.fromPalette(const ChromePalette.light());
      double scaleOf(String id) => tester
          .widget<Transform>(find.byKey(ValueKey('attach-tab-indicator-$id')))
          .transform
          .storage[0];
      double alphaOf(String id) {
        final box = find.descendant(
          of: find.byKey(ValueKey('attach-tab-indicator-$id')),
          matching: find.byType(DecoratedBox),
        );
        return (tester.widget<DecoratedBox>(box).decoration as BoxDecoration)
            .color!
            .a;
      }

      expect(scaleOf('gallery'), 1);
      expect(alphaOf('gallery'), closeTo(tokens.tabIndicator.a, 1e-6));
      expect(scaleOf('files'), closeTo(0.6, 1e-6));
      expect(alphaOf('files'), 0);

      await tester.tap(rig.tab('files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scaleOf('files'), inExclusiveRange(0.6, 1));
      expect(alphaOf('files'), inExclusiveRange(0, tokens.tabIndicator.a));
      expect(scaleOf('gallery'), inExclusiveRange(0.6, 1));

      await tester.pump(const Duration(milliseconds: 240));
      expect(scaleOf('files'), 1);
      expect(alphaOf('files'), closeTo(tokens.tabIndicator.a, 1e-6));
      expect(alphaOf('gallery'), 0);
      await tester.pumpAndSettle();
    });

    testWidgets('as the selection fills, the bar drops 36 and fades as one, '
        'its glass reading the scene on every frame', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      final rest = tester.getRect(find.byKey(const ValueKey('attach-tab-bar')));
      rig.selection.toggle(AttachItems.photo('p'));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final shown = _barGlass(tester).opacity;
        final drop =
            tester.getRect(find.byKey(const ValueKey('attach-tab-bar'))).top -
            rest.top;
        expect(drop, closeTo(36 * (1 - shown), 0.01), reason: 'frame $i');
        final filters = _barFilters(tester);
        expect(filters, isNotEmpty, reason: 'frame $i');
        for (final filter in filters) {
          expect(_fadingAbove(filter), isEmpty, reason: 'frame $i');
        }
      }
      await tester.pumpAndSettle();
      expect(_barGlass(tester).opacity, 0);

      rig.selection.clear();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(_barGlass(tester).opacity, inExclusiveRange(0, 1));
      for (final filter in _barFilters(tester)) {
        expect(_fadingAbove(filter), isEmpty);
      }
      await tester.pumpAndSettle();
      expect(_barGlass(tester).opacity, 1);
    });

    testWidgets('it comes back from 44 below as the sheet leaves its top', (
      tester,
    ) async {
      late AttachPageScope gallery;
      await PagesRig.open(
        tester,
        policy: android,
        pages: [
          rowsPage('gallery', onScope: (s) => gallery = s),
          rowsPage('files'),
        ],
      );
      final rest = tester.getRect(find.byKey(const ValueKey('attach-tab-bar')));
      gallery.requestExpansion();
      await tester.pumpAndSettle();
      expect(_barGlass(tester).opacity, 0);
      expect(
        tester.getRect(find.byKey(const ValueKey('attach-tab-bar'))).top,
        rest.top + 44,
      );

      final sheet = AttachSheetController.of(
        tester.element(find.byKey(const ValueKey('gallery-row-0'))),
      );
      unawaited(sheet.collapse());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      final shown = _barGlass(tester).opacity;
      expect(shown, inExclusiveRange(0, 1));
      expect(
        tester.getRect(find.byKey(const ValueKey('attach-tab-bar'))).top -
            rest.top,
        closeTo(44 * (1 - shown), 0.01),
      );
      for (final filter in _barFilters(tester)) {
        expect(_fadingAbove(filter), isEmpty);
      }
      await tester.pumpAndSettle();
    });

    testWidgets("a host's style: its own glass and tab colours", (
      tester,
    ) async {
      final rig = await PagesRig.open(
        tester,
        policy: const _CustomTabs(),
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      expect(
        _barGlass(tester).material,
        _CustomTabs.glass.copyWith(strokeWidth: 1),
      );
      final label = tester.widget<Text>(
        find.descendant(of: rig.tab('files'), matching: find.text('files')),
      );
      expect(label.style!.color, const Color(0xFF00FF00));
    });

    testWidgets('a page with a shown icon of its own wears it when shown', (
      tester,
    ) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [
          AttachPage(
            id: const AttachPageId('gallery'),
            label: 'gallery',
            icon: const SizedBox(key: ValueKey('outline'), width: 24),
            selectedIcon: const SizedBox(key: ValueKey('filled'), width: 24),
            builder: (context, scope) => const SizedBox.expand(),
          ),
          rowsPage('files'),
        ],
      );
      expect(find.byKey(const ValueKey('filled')), findsOneWidget);
      await rig.tapTab('files');
      expect(find.byKey(const ValueKey('filled')), findsNothing);
      expect(find.byKey(const ValueKey('outline')), findsOneWidget);
    });
  });

  group('Android widths', () {
    test('a label plus 16 a side, 8 a side from 56, at most 84', () {
      expect(android.tabWidths([30], 0), [62]);
      expect(android.tabWidths([48], 0), [48 + 2 * 12]);
      expect(android.tabWidths([56], 0), [72]);
      expect(android.tabWidths([80], 0), [84]);
    });

    test('room left over is shared evenly', () {
      expect(android.tabWidths([30, 30], 200), [100, 100]);
    });
  });

  group('iOS widths', () {
    test('160 for two tabs, 240 for three, 300 for four, else the screen', () {
      double bar(int n, double available) =>
          ios
              .tabWidths(List.filled(n, 30), available)
              .fold<double>(0, (a, b) => a + b) +
          2 * ios.tabBar.innerPadding;
      expect(bar(2, 346), 160);
      expect(bar(3, 346), 240);
      expect(bar(4, 346), 300);
      expect(bar(5, 346), 346);
    });
  });

  group('Android pop-in', () {
    const popIn = AttachTabPopIn(
      delay: Duration(milliseconds: 20),
      step: Duration(milliseconds: 32),
      anchorIndex: 3,
      overshoot: 1.1,
      grow: Duration(milliseconds: 200),
      growCurve: Cubic(0, 0, 0.58, 1),
      fadeCurve: Cubic(0.42, 0, 0.58, 1),
      settle: Duration(milliseconds: 100),
      settleCurve: Cubic(0.42, 0, 1, 1),
    );

    test('is the policy\'s', () {
      final style = android.tabBar.popIn!;
      expect(style.step, popIn.step);
      expect(style.overshoot, 1.1);
      expect(style.grow, const Duration(milliseconds: 200));
      expect(style.settle, const Duration(milliseconds: 100));
      expect(ios.tabBar.popIn, isNull);
    });

    test('the last of four tabs starts first, 32 ms apart', () {
      expect(popIn.startOf(3), Duration.zero);
      expect(popIn.startOf(0), const Duration(milliseconds: 96));
      expect(popIn.at(0, const Duration(milliseconds: 96)).scale, 0);
      expect(
        popIn.at(3, const Duration(milliseconds: 200)).scale,
        closeTo(1.1, 1e-9),
      );
      expect(popIn.at(3, const Duration(milliseconds: 300)).scale, 1);
      expect(popIn.at(0, const Duration(milliseconds: 396)).scale, 1);
    });

    testWidgets('tabs pop in staggered and settle at full size', (
      tester,
    ) async {
      await PagesRig.open(
        tester,
        policy: android,
        settle: false,
        pages: [
          rowsPage('gallery'),
          rowsPage('files'),
          rowsPage('music'),
          rowsPage('contact'),
        ],
      );
      double scaleOf(String id) => tester
          .widget<Transform>(find.byKey(ValueKey('attach-tab-pop-$id')))
          .transform
          .storage[0];

      await tester.pump(const Duration(milliseconds: 100));
      expect(scaleOf('contact'), greaterThan(scaleOf('gallery')));

      await tester.pumpAndSettle();
      for (final id in ['gallery', 'files', 'music', 'contact']) {
        expect(scaleOf(id), closeTo(1, 1e-6));
      }
    });
  });

  group('switch', () {
    testWidgets('Android: for 180 ms both pages drop together, the new one '
        'fading in over the old; then the new one springs up from 78', (
      tester,
    ) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      final sheetTop = rig.top;
      double rowTop(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('$id-row-0'))).dy - sheetTop;
      double opacityOf(String id) => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(ValueKey('$id-row-0')),
                  matching: find.byKey(ValueKey('attach-page-stage-$id')),
                )
                .first,
          )
          .opacity;

      await tester.tap(rig.tab('files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      // Mid out phase: both pages at one drop; the old one opaque, the new
      // one partly in, painted over it.
      final drop = rowTop('gallery');
      expect(drop, inExclusiveRange(0, 78));
      expect(rowTop('files'), closeTo(drop, 0.5));
      expect(opacityOf('gallery'), 1);
      expect(opacityOf('files'), inExclusiveRange(0, 1));
      expect(opacityOf('files'), closeTo(drop / 78, 0.02));
      final stage = tester
          .widgetList<Positioned>(
            find.descendant(
              of: find.byKey(const ValueKey('attach-page-area')),
              matching: find.byType(Positioned),
            ),
          )
          .map((p) => (p.key! as ValueKey<Object?>).value)
          .toList();
      expect(stage.indexOf('files'), greaterThan(stage.indexOf('gallery')));

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      // The spring: the new page opaque, rising from 78; the old one gone.
      expect(rig.shows('gallery'), isFalse);
      expect(opacityOf('files'), 1);
      expect(rowTop('files'), inInclusiveRange(1, 78));

      await tester.pumpAndSettle();
      expect(rowTop('files'), closeTo(0, 0.5));
    });

    testWidgets('a tap during a switch waits (Android)', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files'), rowsPage('music')],
      );
      await tester.tap(rig.tab('files'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(rig.tab('music'));
      await tester.pumpAndSettle();
      expect(rig.shows('files'), isTrue);
      expect(rig.shows('music'), isFalse);
    });

    testWidgets('iOS: a 0.23 s cross-fade as the new page rises 10', (
      tester,
    ) async {
      final rig = await PagesRig.open(
        tester,
        policy: ios,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      final sheetTop = rig.top;
      await tester.tap(rig.tab('files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final rise =
          tester.getTopLeft(find.byKey(const ValueKey('files-row-0'))).dy -
          sheetTop;
      expect(rise, inExclusiveRange(0, 10));
      expect(
        find.byKey(const ValueKey('gallery-row-0')).evaluate(),
        isNotEmpty,
      );

      await tester.pumpAndSettle();
      expect(rig.shows('gallery'), isFalse);
    });
  });

  test('Android: the bar drops 36 as it leaves; iOS: it shrinks to 0.85', () {
    expect(android.tabBar.hideDrop, 36);
    expect(
      android.tabBar.hideMotion,
      const MotionSpec(Duration(milliseconds: 180), Curves.decelerate),
    );
    expect(ios.tabBar.hideScale, 0.85);
    expect(
      ios.tabBar.hideMotion,
      const MotionSpec(Duration(milliseconds: 100), Curves.linear),
    );
  });

  group('iOS lens', () {
    double lensLeft(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(const ValueKey('attach-tab-lens'))).dx;

    testWidgets('sits 3 inside the shown tab and slides to a tapped one', (
      tester,
    ) async {
      final rig = await PagesRig.open(
        tester,
        policy: ios,
        pages: [rowsPage('gallery'), rowsPage('files'), rowsPage('music')],
      );
      final bar = tester.getRect(find.byKey(const ValueKey('attach-tab-bar')));
      expect(bar.width, 240);
      final lens = find.byKey(const ValueKey('attach-tab-lens'));
      expect(tester.getSize(lens), const Size(74, 56));
      expect(lensLeft(tester) - bar.left, closeTo(3, 0.01));

      await rig.tapTab('music');
      expect(lensLeft(tester) - bar.left, closeTo(163, 0.5));
    });

    testWidgets('a drag across the tabs moves it and selects where it ends', (
      tester,
    ) async {
      final rig = await PagesRig.open(
        tester,
        policy: ios,
        pages: [rowsPage('gallery'), rowsPage('files'), rowsPage('music')],
      );
      await tester.drag(rig.tab('gallery'), const Offset(90, 0));
      await tester.pumpAndSettle();
      expect(rig.shows('files'), isTrue);
    });

    test('Android marks the shown tab with a fill, not a lens', () {
      expect(android.tabBar.lens, isNull);
      expect(ios.tabBar.lens!.radius, 28);
      expect(ios.tabBar.lens!.inset, 3);
    });
  });
}
