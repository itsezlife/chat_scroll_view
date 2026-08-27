import 'package:flutter/foundation.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';

/// Authoritative catalog contents for one panel surface.
///
/// Owns section/leaf structure and (in subclasses) fetch orchestration.
/// Does **not** own the process-wide asset decode store
/// (`CatalogAssetCache`) — leaf readiness lives there; this type only
/// exposes what to project.
///
/// The viewport listens and projects. It MUST NOT fetch inside layout or
/// paint. After a logical mutation that should relayout, implementations
/// MUST call [notifyDataChanged] **exactly once** (not per leaf).
///
/// ## Listeners
///
/// [addDataListener] / [removeDataListener], synchronous notify (no
/// `Stream`). Dedup-on-add: the same callback twice is a no-op. Dispatch
/// iterates a snapshot so listeners MAY add/remove during notify.
///
/// ## Empty vs loading
///
/// [sections] returning an empty list is a **confirmed empty** catalog —
/// the viewport projects zero slots (content extent collapses to vertical
/// padding only). Distinct “initial loading” overlays are a host/chrome
/// concern for now; this base type does not model a separate loading flag.
///
/// ## Dispose
///
/// After [dispose], mutations SHOULD be silent no-ops. Subclasses that
/// override [dispose] MUST call `super.dispose()` (or [disposeDataListeners])
/// so viewport subscriptions cannot fire into a dead source.
abstract class CatalogDataSource {
  final _dataListeners = <VoidCallback>[];

  /// Current sections in display order (read-only to callers).
  ///
  /// Empty list is a confirmed empty catalog. Section order is paint /
  /// extent order — first section’s header is nearest the catalog top.
  /// Implementations SHOULD return an unmodifiable or defensively copied
  /// list so hosts cannot mutate projection input behind the source’s back.
  List<CatalogSection> get sections;

  /// Subscribe to catalog changes. Same [callback] twice is a no-op.
  void addDataListener(VoidCallback callback) {
    if (_dataListeners.contains(callback)) return;
    _dataListeners.add(callback);
  }

  /// Unsubscribe from catalog changes. Unknown [callback] is a no-op.
  void removeDataListener(VoidCallback callback) {
    _dataListeners.remove(callback);
  }

  /// Notify listeners that catalog contents changed.
  ///
  /// Snapshot iteration — listeners MAY add/remove during dispatch.
  /// Call **once per logical mutation**, not per leaf insert. The viewport
  /// responds by marking layout + paint dirty and reprojecting slots.
  @protected
  void notifyDataChanged() {
    for (final cb in List<VoidCallback>.of(_dataListeners, growable: false)) {
      cb();
    }
  }

  /// Clears listeners. Subclasses that override [dispose] MUST call this
  /// (or `super.dispose()`).
  @protected
  void disposeDataListeners() {
    _dataListeners.clear();
  }

  /// Releases listeners and subclass resources. Idempotent when overridden
  /// carefully (guard with a disposed flag before clearing).
  @mustCallSuper
  void dispose() {
    disposeDataListeners();
  }
}
