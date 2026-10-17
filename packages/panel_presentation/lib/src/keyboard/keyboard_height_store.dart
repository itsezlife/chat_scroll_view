import 'dart:async';

import 'package:content_model/content_model.dart';

/// Which way up the window is: the key a keyboard height is remembered under.
enum PanelOrientation {
  /// The window is taller than wide, or square.
  portrait,

  /// The window is wider than tall.
  landscape,
}

/// The soft keyboard heights the keyboard-replacement presentation remembers,
/// one per [PanelOrientation], so the panel opens at the size of the keyboard
/// it replaces even before that keyboard has been shown in this session.
///
/// ## Ownership
///
/// **Owns:** the sanity floor, the rule for what replaces a stored height and
/// the layout of the stored values in its namespace.
///
/// **Does not own:** deciding when a height was measured (the strategy
/// records only settled readings), the default used when nothing is stored
/// (a [KeyboardReplacementTuning]) or the storage itself ([KeyValueStore]).
///
/// ## Heights
///
/// A height is the content height of the keyboard in logical pixels, without
/// the bottom safe area. One below [minSaneHeight] is a reading taken in the
/// middle of an animation, never a keyboard, and is neither stored nor
/// trusted when read back.
///
/// The latest reading replaces the stored height, taller or shorter, as the
/// reference client keeps the last keyboard it measured: a keyboard that got
/// shorter (another layout, a suggestion bar turned off) must not leave the
/// panel taller than it for good. A sample from a hiding animation never gets
/// here: the slot records only settled readings of a raised keyboard.
///
/// ## Loading
///
/// Created already loaded by [open], so [heightFor] is synchronous. A failure
/// to persist is reported to the zone and leaves the height in memory.
final class KeyboardHeightStore {
  KeyboardHeightStore._(this._store, this._heights);

  /// Loads the heights stored in [store].
  ///
  /// A value that is unreadable, of another layout version or below
  /// [minSaneHeight] is dropped as if it were missing.
  static Future<KeyboardHeightStore> open(KeyValueStore store) async {
    final heights = <PanelOrientation, double>{};
    for (final orientation in PanelOrientation.values) {
      final stored = await store.read(namespace, _keyOf(orientation));
      final height = _decode(stored);
      if (height != null) heights[orientation] = height;
    }
    return KeyboardHeightStore._(store, heights);
  }

  /// The namespace this store owns in the [KeyValueStore].
  static const String namespace = 'panel_presentation';

  /// The shortest height that counts as a keyboard.
  static const double minSaneHeight = 180;

  static const int _version = 1;

  final KeyValueStore _store;
  final Map<PanelOrientation, double> _heights;

  /// The remembered keyboard height for [orientation], or null when none was.
  double? heightFor(PanelOrientation orientation) => _heights[orientation];

  /// Remembers [height] as the keyboard height for [orientation] when it
  /// qualifies, and completes once it is persisted.
  ///
  /// Does nothing for a height that is not finite, below [minSaneHeight] or
  /// equal to the stored one.
  Future<void> record(PanelOrientation orientation, double height) async {
    if (!height.isFinite || height < minSaneHeight) return;
    if (_heights[orientation] == height) return;
    _heights[orientation] = height;
    try {
      await _store.write(
        namespace,
        _keyOf(orientation),
        StoredValue('$height', version: _version),
      );
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  static String _keyOf(PanelOrientation orientation) =>
      'height.${orientation.name}';

  static double? _decode(StoredValue? stored) {
    if (stored == null || stored.version != _version) return null;
    final height = double.tryParse(stored.value);
    if (height == null || !height.isFinite || height < minSaneHeight) {
      return null;
    }
    return height;
  }
}
