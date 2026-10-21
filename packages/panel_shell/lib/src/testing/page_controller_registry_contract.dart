import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/src/page/page_controller_registry.dart';

/// The behaviour every [PageControllerRegistry] must have, as a test suite to
/// run against an implementation.
abstract final class PageControllerRegistryContract {
  /// Runs the [PageControllerRegistry] contract against the registries
  /// [create] returns.
  ///
  /// [create] is called once per test and must return an empty registry.
  /// [disposeAll] releases the controllers it kept, whatever disposal means for
  /// the implementation (the shell controller's registry disposes with its
  /// owner, the fake on request); the contract only checks that every kept
  /// controller is disposed exactly once.
  static void run(
    PageControllerRegistry Function() create,
    void Function(PageControllerRegistry registry) disposeAll,
  ) {
    group('PageControllerRegistry contract', () {
      late PageControllerRegistry registry;

      setUp(() => registry = create());

      test('creates a controller on the first request and reuses it', () {
        var created = 0;
        final first = registry.obtain('emoji', () {
          created++;
          return _Counting();
        });
        final second = registry.obtain('emoji', () {
          created++;
          return _Counting();
        });

        expect(second, same(first));
        expect(created, 1);
      });

      test('keeps one controller per page id', () {
        final emoji = registry.obtain('emoji', _Counting.new);
        final stickers = registry.obtain('stickers', _Counting.new);

        expect(stickers, isNot(same(emoji)));
      });

      test('peek never creates', () {
        expect(registry.peek<_Counting>('emoji'), isNull);

        final kept = registry.obtain('emoji', _Counting.new);

        expect(registry.peek<_Counting>('emoji'), same(kept));
      });

      test('a page id asked for two different types is a StateError', () {
        registry.obtain('emoji', _Counting.new);

        expect(
          () => registry.obtain<_Other>('emoji', _Other.new),
          throwsStateError,
        );
        expect(() => registry.peek<_Other>('emoji'), throwsStateError);
      });

      test('disposes every kept controller exactly once', () {
        final a = registry.obtain('emoji', _Counting.new);
        final b = registry.obtain('stickers', _Counting.new);

        disposeAll(registry);
        disposeAll(registry);

        expect(a.disposals, 1);
        expect(b.disposals, 1);
      });
    });
  }
}

class _Counting implements PanelPageController {
  int disposals = 0;

  @override
  void dispose() => disposals++;
}

class _Other implements PanelPageController {
  @override
  void dispose() {}
}
