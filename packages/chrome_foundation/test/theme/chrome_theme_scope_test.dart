import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _light = ChromePalette.light();
const _dark = ChromePalette.dark();

void main() {
  group('missing scope', () {
    testWidgets('every lookup asserts', (tester) async {
      final lookups = <String, void Function(BuildContext)>{
        'of': ChromeThemeScope.of,
        'paletteOf': ChromeThemeScope.paletteOf,
        'composerOf': ChromeThemeScope.composerOf,
        'panelOf': ChromeThemeScope.panelOf,
        'actionOf': ChromeThemeScope.actionOf,
        'placeholderOf': ChromeThemeScope.placeholderOf,
        'glassOf': ChromeThemeScope.glassOf,
        'selectionMenuOf': ChromeThemeScope.selectionMenuOf,
        'spoilerOf': ChromeThemeScope.spoilerOf,
      };
      for (final entry in lookups.entries) {
        late BuildContext context;
        await tester.pumpWidget(
          Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        );
        expect(
          () => entry.value(context),
          throwsFlutterError,
          reason: entry.key,
        );
      }
    });

    testWidgets('the message names the missing scope', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      expect(
        () => ChromeThemeScope.panelOf(context),
        throwsA(
          isA<FlutterError>().having(
            (e) => e.toString(),
            'message',
            contains('ChromeThemeScope'),
          ),
        ),
      );
    });

    testWidgets('a scope without that group still asserts', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        ChromeThemeScope(
          composer: ComposerTokens.fromPalette(_light),
          child: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(ChromeThemeScope.composerOf(context).text, _light.onSurface);
      expect(() => ChromeThemeScope.panelOf(context), throwsFlutterError);
    });
  });

  group('root scope', () {
    testWidgets('a palette derives every group', (tester) async {
      late ChromeThemeData seen;
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: _dark,
          child: Builder(
            builder: (c) {
              seen = ChromeThemeScope.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, ChromeThemeData.fromPalette(_dark));
    });

    testWidgets('a supplied group wins over the derived one', (tester) async {
      final panel = PanelTokens.fromPalette(
        _light,
      ).copyWith(background: const Color(0xFF123456));
      late PanelTokens seenPanel;
      late ComposerTokens seenComposer;
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: _light,
          panel: panel,
          child: Builder(
            builder: (c) {
              seenPanel = ChromeThemeScope.panelOf(c);
              seenComposer = ChromeThemeScope.composerOf(c);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seenPanel, panel);
      expect(seenComposer, ComposerTokens.fromPalette(_light));
    });

    testWidgets('.data supplies a whole theme verbatim', (tester) async {
      final data = ChromeThemeData.fromPalette(_light).copyWith(
        action: ActionTokens.fromPalette(
          _light,
        ).copyWith(send: const Color(0xFFABCDEF)),
      );
      late ChromeThemeData seen;
      await tester.pumpWidget(
        ChromeThemeScope.data(
          data: data,
          child: Builder(
            builder: (c) {
              seen = ChromeThemeScope.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, data);
    });
  });

  group('nesting', () {
    testWidgets('an inner scope overrides only the groups it supplies', (
      tester,
    ) async {
      final innerComposer = ComposerTokens.fromPalette(
        _light,
      ).copyWith(background: const Color(0xFF445566));
      late ChromeThemeData seen;
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: _dark,
          child: ChromeThemeScope(
            composer: innerComposer,
            child: Builder(
              builder: (c) {
                seen = ChromeThemeScope.of(c);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(seen.composer, innerComposer);
      expect(seen.palette, _dark);
      expect(seen.panel, PanelTokens.fromPalette(_dark));
      expect(seen.action, ActionTokens.fromPalette(_dark));
    });

    testWidgets('an inner palette re-derives the groups it does not supply', (
      tester,
    ) async {
      final outerPanel = PanelTokens.fromPalette(
        _dark,
      ).copyWith(background: const Color(0xFF010101));
      late ChromeThemeData seen;
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: _dark,
          panel: outerPanel,
          child: ChromeThemeScope(
            palette: _light,
            child: Builder(
              builder: (c) {
                seen = ChromeThemeScope.of(c);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(seen, ChromeThemeData.fromPalette(_light));
    });

    testWidgets('three levels resolve each group at its nearest supplier', (
      tester,
    ) async {
      final mid = PanelTokens.fromPalette(
        _dark,
      ).copyWith(background: const Color(0xFF0A0B0C));
      final inner = ComposerTokens.fromPalette(
        _dark,
      ).copyWith(text: const Color(0xFF0D0E0F));
      late ChromeThemeData seen;
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: _light,
          child: ChromeThemeScope(
            panel: mid,
            child: ChromeThemeScope(
              composer: inner,
              child: Builder(
                builder: (c) {
                  seen = ChromeThemeScope.of(c);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(seen.composer, inner);
      expect(seen.panel, mid);
      expect(seen.palette, _light);
      expect(seen.action, ActionTokens.fromPalette(_light));
    });
  });

  group('rebuilds', () {
    testWidgets('a dependent on one group ignores changes to another', (
      tester,
    ) async {
      var composerBuilds = 0;
      var panelBuilds = 0;
      // One child instance, so only the scope's notifications rebuild it.
      final child = Column(
        children: [
          Builder(
            builder: (c) {
              ChromeThemeScope.composerOf(c);
              composerBuilds++;
              return const SizedBox();
            },
          ),
          Builder(
            builder: (c) {
              ChromeThemeScope.panelOf(c);
              panelBuilds++;
              return const SizedBox();
            },
          ),
        ],
      );
      Widget app(ChromeThemeData data) =>
          ChromeThemeScope.data(data: data, child: child);
      final base = ChromeThemeData.fromPalette(_light);
      await tester.pumpWidget(app(base));
      expect((composerBuilds, panelBuilds), (1, 1));

      await tester.pumpWidget(
        app(
          base.copyWith(
            panel: base.panel.copyWith(background: const Color(0xFF111111)),
          ),
        ),
      );
      expect((composerBuilds, panelBuilds), (1, 2));

      await tester.pumpWidget(
        app(
          base.copyWith(
            panel: base.panel.copyWith(background: const Color(0xFF111111)),
          ),
        ),
      );
      expect((composerBuilds, panelBuilds), (1, 2), reason: 'equal theme');
    });

    testWidgets('an inner scope shields its dependents from the outer group', (
      tester,
    ) async {
      var builds = 0;
      final inner = PanelTokens.fromPalette(_light);
      final child = Builder(
        builder: (c) {
          ChromeThemeScope.panelOf(c);
          builds++;
          return const SizedBox();
        },
      );
      Widget app(ChromePalette outer) => ChromeThemeScope(
        palette: outer,
        child: ChromeThemeScope(panel: inner, child: child),
      );
      await tester.pumpWidget(app(_light));
      await tester.pumpWidget(app(_dark));
      expect(builds, 1, reason: 'the inner scope is the panel supplier');
    });
  });

  group('selection menu and spoiler groups', () {
    testWidgets('an inner scope overrides only the menu', (tester) async {
      final menu = SelectionMenuTokens.fromPalette(
        _light,
      ).copyWith(text: const Color(0xFF123456));
      late SelectionMenuTokens seenMenu;
      late SpoilerTokens seenSpoiler;
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: _dark,
          child: ChromeThemeScope(
            selectionMenu: menu,
            child: Builder(
              builder: (c) {
                seenMenu = ChromeThemeScope.selectionMenuOf(c);
                seenSpoiler = ChromeThemeScope.spoilerOf(c);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(seenMenu, menu);
      expect(seenSpoiler, SpoilerTokens.fromPalette(_dark));
    });

    testWidgets('a spoiler override reaches its dependents only', (
      tester,
    ) async {
      var spoilerBuilds = 0;
      var menuBuilds = 0;
      final spoiler = Builder(
        builder: (c) {
          ChromeThemeScope.spoilerOf(c);
          spoilerBuilds++;
          return const SizedBox();
        },
      );
      final menu = Builder(
        builder: (c) {
          ChromeThemeScope.selectionMenuOf(c);
          menuBuilds++;
          return const SizedBox();
        },
      );
      Widget app(SpoilerTokens tokens) => ChromeThemeScope(
        palette: _light,
        spoiler: tokens,
        child: Column(children: [spoiler, menu]),
      );
      await tester.pumpWidget(app(SpoilerTokens.fromPalette(_light)));
      await tester.pumpWidget(
        app(const SpoilerTokens(color: Color(0xFFFF0000))),
      );
      expect(spoilerBuilds, 2);
      expect(menuBuilds, 1);
    });

    testWidgets('an animated scope interpolates the menu colours', (
      tester,
    ) async {
      late SelectionMenuTokens seen;
      Widget app(ChromePalette palette) => AnimatedChromeThemeScope(
        palette: palette,
        duration: const Duration(milliseconds: 100),
        child: Builder(
          builder: (c) {
            seen = ChromeThemeScope.selectionMenuOf(c);
            return const SizedBox();
          },
        ),
      );
      await tester.pumpWidget(app(_light));
      await tester.pumpWidget(app(_dark));
      await tester.pump(const Duration(milliseconds: 50));
      final light = SelectionMenuTokens.fromPalette(_light);
      final dark = SelectionMenuTokens.fromPalette(_dark);
      expect(seen.background, isNot(anyOf(light.background, dark.background)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(seen, dark);
    });
  });

  group('animated', () {
    testWidgets('interpolates between two themes', (tester) async {
      final light = ChromeThemeData.fromPalette(_light);
      final dark = ChromeThemeData.fromPalette(_dark);
      late ChromeThemeData seen;
      Widget app(ChromeThemeData data) => AnimatedChromeThemeScope(
        palette: data.palette,
        composer: data.composer,
        panel: data.panel,
        action: data.action,
        placeholder: data.placeholder,
        glass: data.glass,
        selectionMenu: data.selectionMenu,
        spoiler: data.spoiler,
        duration: const Duration(milliseconds: 200),
        child: Builder(
          builder: (c) {
            seen = ChromeThemeScope.of(c);
            return const SizedBox();
          },
        ),
      );
      await tester.pumpWidget(app(light));
      expect(seen, light);

      await tester.pumpWidget(app(dark));
      await tester.pump(const Duration(milliseconds: 100));
      expect(seen, isNot(light));
      expect(seen, isNot(dark));
      expect(
        seen.palette.surface,
        isNot(anyOf(light.palette.surface, dark.palette.surface)),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(seen, dark);
    });

    testWidgets('a palette alone animates the derived groups', (tester) async {
      late ChromePalette seen;
      Widget app(ChromePalette palette) => AnimatedChromeThemeScope(
        palette: palette,
        duration: const Duration(milliseconds: 100),
        child: Builder(
          builder: (c) {
            seen = ChromeThemeScope.paletteOf(c);
            return const SizedBox();
          },
        ),
      );
      await tester.pumpWidget(app(_light));
      await tester.pumpWidget(app(_dark));
      await tester.pump(const Duration(milliseconds: 100));
      expect(seen, _dark);
    });

    testWidgets('a nested animated scope animates only its group', (
      tester,
    ) async {
      final a = ComposerTokens.fromPalette(_light);
      final b = ComposerTokens.fromPalette(_dark);
      late ChromeThemeData seen;
      Widget app(ComposerTokens composer) => ChromeThemeScope(
        palette: _light,
        child: AnimatedChromeThemeScope(
          composer: composer,
          duration: const Duration(milliseconds: 100),
          curve: Curves.linear,
          child: Builder(
            builder: (c) {
              seen = ChromeThemeScope.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(app(a));
      await tester.pumpWidget(app(b));
      await tester.pump(const Duration(milliseconds: 50));
      expect(seen.composer, ComposerTokens.lerp(a, b, 0.5));
      expect(seen.panel, PanelTokens.fromPalette(_light));
      await tester.pump(const Duration(milliseconds: 50));
      expect(seen.composer, b);
    });
  });
}
