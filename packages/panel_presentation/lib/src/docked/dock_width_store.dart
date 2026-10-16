import 'dart:async';

import 'package:content_model/content_model.dart';

/// The width the user dragged the dock to, remembered across sessions.
///
/// ## Ownership
///
/// **Owns:** what counts as a width worth keeping, and the layout of the
/// stored value in its namespace.
///
/// **Does not own:** the bounds a dock is held to (the policy's
/// `dockMinWidth` and `dockMaxWidth`, applied when a width is used), the drag
/// itself (the controller's `resizeDock`), or the storage ([KeyValueStore]).
/// It is a sibling of the keyboard heights store: a size of the panel's own
/// chrome, kept apart from the typed choices of a [PreferenceStore].
///
/// ## Width
///
/// A width is a number of logical pixels. One that is not finite or not
/// positive is no width: it is neither stored nor trusted when read back. The
/// last width recorded replaces the one before it, shorter or longer: unlike a
/// keyboard height, a width is a choice.
///
/// ## Loading
///
/// Created already loaded by [open], so [width] is synchronous. A failure to
/// persist is reported to the zone and leaves the width in memory.
final class DockWidthStore {
  DockWidthStore._(this._store, this._width);

  /// Loads the width stored in [store].
  ///
  /// A value that is unreadable, of another layout version or not a width is
  /// dropped as if it were missing.
  static Future<DockWidthStore> open(KeyValueStore store) async =>
      DockWidthStore._(store, _decode(await store.read(namespace, _key)));

  /// The namespace this store owns in the [KeyValueStore].
  static const String namespace = 'panel_presentation';

  static const String _key = 'dockWidth';
  static const int _version = 1;

  final KeyValueStore _store;
  double? _width;

  /// The remembered dock width, or null when none was.
  double? get width => _width;

  /// Remembers [width] and completes once it is persisted.
  ///
  /// Does nothing for a width that is not a width, or the one already kept.
  Future<void> record(double width) async {
    if (!_isWidth(width) || width == _width) return;
    _width = width;
    try {
      await _store.write(
        namespace,
        _key,
        StoredValue('$width', version: _version),
      );
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  static bool _isWidth(double width) => width.isFinite && width > 0;

  static double? _decode(StoredValue? stored) {
    if (stored == null || stored.version != _version) return null;
    final width = double.tryParse(stored.value);
    return width != null && _isWidth(width) ? width : null;
  }
}
