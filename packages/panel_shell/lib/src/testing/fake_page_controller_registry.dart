import 'package:panel_shell/src/page/page_controller_registry.dart';

/// A [PageControllerRegistry] for tests that records how it was used.
///
/// Follows the contract of `PanelPageControllers` (one controller per page
/// id, created on first request, type mismatch is a [StateError]) and never
/// disposes on its own: a test calls [disposeAll] to see the controllers go.
final class FakePageControllerRegistry implements PageControllerRegistry {
  final _controllers = <String, PanelPageController>{};

  /// Page ids in the order their controllers were created.
  final List<String> createdIds = [];

  /// How many times [obtain] was called, created or not.
  int obtainCount = 0;

  @override
  T obtain<T extends PanelPageController>(String pageId, T Function() create) {
    obtainCount++;
    final existing = _controllers[pageId];
    if (existing != null) return _typed<T>(pageId, existing);
    final created = create();
    _controllers[pageId] = created;
    createdIds.add(pageId);
    return created;
  }

  @override
  T? peek<T extends PanelPageController>(String pageId) {
    final existing = _controllers[pageId];
    return existing == null ? null : _typed<T>(pageId, existing);
  }

  /// Disposes every controller kept and forgets them.
  void disposeAll() {
    final kept = _controllers.values.toList(growable: false);
    _controllers.clear();
    for (final controller in kept) {
      controller.dispose();
    }
  }

  T _typed<T extends PanelPageController>(
    String pageId,
    PanelPageController existing,
  ) {
    if (existing is T) return existing;
    throw StateError(
      'Page "$pageId" keeps a ${existing.runtimeType}, not a $T.',
    );
  }
}
