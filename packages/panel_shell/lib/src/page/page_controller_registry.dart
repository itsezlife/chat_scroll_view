/// Something a page keeps across being unmounted: a scroll controller, the
/// collections it loaded, a search source.
///
/// The shell controller owns instances through a [PageControllerRegistry] and
/// calls [dispose] when the shell controller itself is disposed, so a page
/// widget that is torn down and rebuilt (a presentation switch, a page swipe
/// off screen) finds the same object and restores its state.
abstract interface class PanelPageController {
  /// Releases the resources of the controller. Called once, by the registry
  /// that owns it.
  void dispose();
}

/// Where a page keeps its [PanelPageController]s, one per page id.
///
/// The registry lives in the shell controller, not in a widget, which is what
/// lets state survive a change of presentation.
abstract interface class PageControllerRegistry {
  /// The controller of type [T] kept for [pageId], created by [create] on the
  /// first request and reused afterwards.
  ///
  /// Throws a [StateError] when [pageId] already keeps a controller that is not
  /// a [T]: one page id holds one controller, and two pieces of code reaching
  /// for different types under the same id is a bug, not a lookup miss.
  T obtain<T extends PanelPageController>(String pageId, T Function() create);

  /// The controller of type [T] kept for [pageId], or null when none exists
  /// yet. Never creates one.
  T? peek<T extends PanelPageController>(String pageId);
}

/// The registry the shell controller owns: an in-memory map that disposes its
/// controllers with [dispose].
final class PanelPageControllers implements PageControllerRegistry {
  final _controllers = <String, PanelPageController>{};
  var _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  @override
  T obtain<T extends PanelPageController>(String pageId, T Function() create) {
    final existing = _controllers[pageId];
    if (existing != null) return _typed<T>(pageId, existing);
    final created = create();
    // Once disposed the registry stops keeping anything, so a late request
    // cannot resurrect a controller nobody will dispose.
    if (!_disposed) _controllers[pageId] = created;
    return created;
  }

  @override
  T? peek<T extends PanelPageController>(String pageId) {
    final existing = _controllers[pageId];
    return switch (existing) {
      final existing? => _typed<T>(pageId, existing),
      null => null,
    };
  }

  /// Disposes every controller kept and forgets them. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
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
    if (existing case final T typed) return typed;
    throw StateError(
      'Page "$pageId" keeps a ${existing.runtimeType}, not a $T.',
    );
  }
}
