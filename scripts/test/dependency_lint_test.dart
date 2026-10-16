import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

/// Builds the graph from `name -> workspace dependencies`; the lint decides
/// from names and edges only.
WorkspaceGraph graphOf(Map<String, Set<String>> edges) => WorkspaceGraph(
  root: '.',
  members: [
    for (final MapEntry(:key, :value) in edges.entries)
      WorkspaceMember(name: key, path: 'packages/$key', dependencies: value),
  ],
);

List<LintRule> rulesOf(Map<String, Set<String>> edges) =>
    DependencyLint.check(graphOf(edges)).map((v) => v.rule).toList();

void main() {
  group('DependencyLint', () {
    test('accepts the target topology of the package architecture spec', () {
      expect(
        DependencyLint.check(
          graphOf({
            'content_model': {},
            'chrome_foundation': {},
            'catalog_assets': {'content_model'},
            'panel_catalog': {'content_model', 'catalog_assets'},
            'emoji_data': {'content_model'},
            'emoji_catalog_pack': {'content_model'},
            'kv_shared_preferences': {'content_model'},
            'panel_shell': {'chrome_foundation', 'content_model'},
            'panel_pages': {
              'panel_shell',
              'panel_catalog',
              'catalog_assets',
              'content_model',
              'chrome_foundation',
            },
            'panel_presentation': {'panel_shell', 'chrome_foundation'},
            'chat_composer': {
              'chrome_foundation',
              'content_model',
              'catalog_assets',
            },
            'example': {
              'panel_pages',
              'panel_presentation',
              'chat_composer',
              'emoji_data',
              'emoji_catalog_pack',
              'kv_shared_preferences',
            },
          }),
        ),
        isEmpty,
      );
    });

    test('accepts the layers as the workspace stands', () {
      expect(
        rulesOf({
          'content_model': {},
          'chrome_foundation': {},
          'catalog_assets': {'content_model'},
          'emoji_data': {'content_model'},
          'panel_catalog': {'catalog_assets', 'content_model'},
          'panel_shell': {'chrome_foundation', 'content_model'},
          'panel_pages': {'panel_catalog', 'panel_shell', 'catalog_assets'},
          'example': {'panel_pages', 'panel_shell', 'emoji_data'},
        }),
        isEmpty,
      );
    });

    group('cycles', () {
      test('reports a two-package cycle once, from its smallest member', () {
        final violations = DependencyLint.check(
          graphOf({
            'beta': {'alpha'},
            'alpha': {'beta'},
          }),
        );

        expect(violations, hasLength(1));
        expect(violations.single.rule, LintRule.dependencyCycle);
        expect(violations.single.subject, 'alpha -> beta -> alpha');
      });

      test('reports a longer cycle through a package outside it', () {
        final violations = DependencyLint.check(
          graphOf({
            'a': {'b'},
            'b': {'c'},
            'c': {'a', 'outside'},
            'outside': {},
          }),
        );

        expect(violations.map((v) => v.subject), ['a -> b -> c -> a']);
      });

      test('a dependency on a package outside the workspace is no edge', () {
        expect(
          rulesOf({
            'a': {'flutter', 'meta'},
          }),
          isEmpty,
        );
      });
    });

    group('leaves', () {
      for (final leaf in ['content_model', 'chrome_foundation']) {
        test('$leaf depending on a workspace package is reported', () {
          final violations = DependencyLint.check(
            graphOf({
              leaf: {'catalog_assets'},
              'catalog_assets': {},
            }),
          );

          expect(violations.map((v) => v.rule), [
            LintRule.leafDependsOnPackage,
          ]);
          expect(violations.single.subject, '$leaf -> catalog_assets');
        });

        test('$leaf depending only on outside packages is a leaf', () {
          expect(
            rulesOf({
              leaf: {'meta', 'flutter'},
            }),
            isEmpty,
          );
        });
      }
    });

    group('panel hosts versus payloads', () {
      for (final host in ['panel_shell', 'panel_pages', 'panel_presentation']) {
        test('$host depending on emoji_catalog_pack is reported', () {
          final violations = DependencyLint.check(
            graphOf({
              host: {'emoji_catalog_pack'},
              'emoji_catalog_pack': {},
            }),
          );

          expect(violations.map((v) => v.rule), [LintRule.forbiddenDependency]);
          expect(violations.single.subject, '$host -> emoji_catalog_pack');
        });
      }

      for (final adapter in [
        'lottie_codec',
        'webm_decoders',
        'catalog_fetcher',
        'disk_fetchers_cache',
      ]) {
        test('depending on the adapter package $adapter is reported', () {
          expect(
            rulesOf({
              'panel_pages': {adapter},
              adapter: {},
            }),
            [LintRule.forbiddenDependency],
          );
        });
      }

      test('a package whose name only starts with "decoder" is no adapter', () {
        expect(
          rulesOf({
            'panel_pages': {'decoderless'},
            'decoderless': {},
          }),
          isEmpty,
        );
      });

      test('other packages may depend on payloads and adapters', () {
        expect(
          rulesOf({
            'example': {'emoji_catalog_pack', 'lottie_codec'},
            'emoji_catalog_pack': {},
            'lottie_codec': {},
          }),
          isEmpty,
        );
      });
    });

    group('transitive dependencies', () {
      test('a host reaching a payload through another member is reported', () {
        final violations = DependencyLint.check(
          graphOf({
            'panel_pages': {'helper'},
            'helper': {'middle'},
            'middle': {'emoji_catalog_pack'},
            'emoji_catalog_pack': {},
          }),
        );

        expect(violations.map((v) => v.rule), [LintRule.forbiddenDependency]);
        expect(
          violations.single.subject,
          'panel_pages -> helper -> middle -> emoji_catalog_pack',
        );
      });

      test('panel_catalog reaching chrome_foundation is reported', () {
        expect(
          DependencyLint.check(
            graphOf({
              'panel_catalog': {'adapter'},
              'adapter': {'chrome_foundation'},
              'chrome_foundation': {},
            }),
          ).single.subject,
          'panel_catalog -> adapter -> chrome_foundation',
        );
      });

      test('a direct edge is reported once, as the shortest path', () {
        expect(
          DependencyLint.check(
            graphOf({
              'panel_shell': {'emoji_catalog_pack', 'helper'},
              'helper': {'emoji_catalog_pack'},
              'emoji_catalog_pack': {},
            }),
          ).map((v) => v.subject),
          ['panel_shell -> emoji_catalog_pack'],
        );
      });
    });

    test('panel_catalog depending on chrome_foundation is reported', () {
      final violations = DependencyLint.check(
        graphOf({
          'panel_catalog': {'chrome_foundation'},
          'chrome_foundation': {},
        }),
      );

      expect(violations.map((v) => v.rule), [LintRule.forbiddenDependency]);
      expect(violations.single.subject, 'panel_catalog -> chrome_foundation');
    });

    group('shared_preferences', () {
      test('is allowed in kv_shared_preferences', () {
        expect(
          rulesOf({
            'content_model': {},
            'kv_shared_preferences': {'content_model', 'shared_preferences'},
          }),
          isEmpty,
        );
      });

      test('is reported in any other member', () {
        final violations = DependencyLint.check(
          graphOf({
            'emoji_data': {'shared_preferences'},
            'kv_shared_preferences': {'shared_preferences'},
          }),
        );

        expect(violations.map((v) => v.rule), [
          LintRule.pluginDependencyOutsideAdapter,
        ]);
        expect(violations.single.subject, 'emoji_data -> shared_preferences');
      });

      test('is reported for its platform implementation packages too', () {
        expect(
          DependencyLint.check(
            graphOf({
              'panel_pages': {'shared_preferences_android'},
            }),
          ).map((v) => v.subject),
          ['panel_pages -> shared_preferences_android'],
        );
      });
    });

    test('reports every kind of violation in one pass, in a stable order', () {
      expect(
        rulesOf({
          'content_model': {'panel_catalog'},
          'panel_catalog': {'content_model', 'chrome_foundation'},
          'chrome_foundation': {},
        }),
        [
          LintRule.dependencyCycle,
          LintRule.leafDependsOnPackage,
          LintRule.forbiddenDependency,
        ],
      );
    });
  });
}
