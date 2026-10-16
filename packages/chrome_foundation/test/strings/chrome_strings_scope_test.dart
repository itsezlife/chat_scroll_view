import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('missing scope', () {
    late BuildContext context;

    testWidgets('every lookup asserts', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      final lookups = <String, void Function(BuildContext)>{
        'of': ChromeStringsScope.of,
        'panelOf': ChromeStringsScope.panelOf,
        'composerOf': ChromeStringsScope.composerOf,
        'semanticsOf': ChromeStringsScope.semanticsOf,
      };
      for (final entry in lookups.entries) {
        expect(
          () => entry.value(context),
          throwsFlutterError,
          reason: entry.key,
        );
      }
    });

    testWidgets('the message names the scope and the fix', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      expect(
        () => ChromeStringsScope.of(context),
        throwsA(
          isA<FlutterError>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('ChromeStringsScope'), contains('ChromeStrings')),
          ),
        ),
      );
    });
  });

  group('lookup', () {
    testWidgets('returns the supplied strings and their groups', (
      tester,
    ) async {
      late ChromeStrings seen;
      late PanelStrings panel;
      late ComposerStrings composer;
      late SemanticsStrings semantics;
      await tester.pumpWidget(
        ChromeStringsScope(
          strings: ChromeStringsPresets.english,
          child: Builder(
            builder: (c) {
              seen = ChromeStringsScope.of(c);
              panel = ChromeStringsScope.panelOf(c);
              composer = ChromeStringsScope.composerOf(c);
              semantics = ChromeStringsScope.semanticsOf(c);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, same(ChromeStringsPresets.english));
      expect(panel, same(seen.panel));
      expect(composer, same(seen.composer));
      expect(semantics, same(seen.semantics));
    });

    testWidgets('a nested scope replaces the strings below it', (tester) async {
      late String inner;
      late String outer;
      await tester.pumpWidget(
        ChromeStringsScope(
          strings: ChromeStringsPresets.english,
          child: Column(
            children: [
              Builder(
                builder: (c) {
                  outer = ChromeStringsScope.panelOf(c).searchHint;
                  return const SizedBox();
                },
              ),
              ChromeStringsScope(
                strings: ChromeStringsPresets.russian,
                child: Builder(
                  builder: (c) {
                    inner = ChromeStringsScope.panelOf(c).searchHint;
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );
      expect(outer, 'Search');
      expect(inner, 'Поиск');
    });

    testWidgets('swapping the strings rebuilds dependents', (tester) async {
      var builds = 0;
      late String hint;
      // One const child, so only a scope notification can rebuild it.
      final probe = Builder(
        builder: (c) {
          builds++;
          hint = ChromeStringsScope.panelOf(c).searchHint;
          return const SizedBox();
        },
      );
      Widget app(ChromeStrings strings) =>
          ChromeStringsScope(strings: strings, child: probe);
      await tester.pumpWidget(app(ChromeStringsPresets.english));
      await tester.pumpWidget(app(ChromeStringsPresets.english));
      expect(builds, 1, reason: 'the same strings do not notify');
      await tester.pumpWidget(app(ChromeStringsPresets.russian));
      expect(builds, 2);
      expect(hint, 'Поиск');
    });
  });
}
