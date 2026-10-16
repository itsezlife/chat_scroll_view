import 'package:chrome_foundation/src/icons/chrome_icon_id.dart';
import 'package:chrome_foundation/src/icons/chrome_icon_painter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;

/// The **chrome icon** registry: semantic id to painter.
///
/// Immutable. [stock] paints every id in [ChromeIconId.stockIds]; a host adds
/// or replaces entries with [withPainters] and supplies the result through a
/// `ChromeIconScope`. An id nobody registered resolves to [fallback], a
/// neutral glyph, so a missing registration is visible but never throws.
@immutable
final class ChromeIconRegistry {
  /// A registry holding exactly [painters].
  const ChromeIconRegistry(this._painters);

  /// The glyph drawn for an id with no registration.
  static const ChromeIconPainter fallback = ChromeIconPainter.font(
    Icons.circle_outlined,
  );

  /// The chrome's own icons.
  static const ChromeIconRegistry stock = ChromeIconRegistry({
    ChromeIconId.emoji: ChromeIconPainter.font(Icons.emoji_emotions_outlined),
    ChromeIconId.keyboard: ChromeIconPainter.font(Icons.keyboard_alt_outlined),
    ChromeIconId.stickers: ChromeIconPainter.font(Icons.sticky_note_2_outlined),
    ChromeIconId.gif: ChromeIconPainter.font(Icons.gif_box_outlined),
    ChromeIconId.send: ChromeIconPainter.font(Icons.send_rounded),
    ChromeIconId.confirm: ChromeIconPainter.font(Icons.check_rounded),
    ChromeIconId.voice: ChromeIconPainter.font(Icons.mic_none_rounded),
    ChromeIconId.attach: ChromeIconPainter.font(Icons.attach_file_rounded),
    ChromeIconId.search: ChromeIconPainter.font(Icons.search_rounded),
    ChromeIconId.close: ChromeIconPainter.font(Icons.close_rounded),
    ChromeIconId.backspace: ChromeIconPainter.font(Icons.backspace_outlined),
    ChromeIconId.reply: ChromeIconPainter.font(Icons.reply_rounded),
    ChromeIconId.edit: ChromeIconPainter.font(Icons.edit_rounded),
  });

  final Map<ChromeIconId, ChromeIconPainter> _painters;

  /// Whether [id] has a registered painter.
  bool contains(ChromeIconId id) => _painters.containsKey(id);

  /// The painter for [id], or [fallback] when none is registered.
  ChromeIconPainter painterFor(ChromeIconId id) => _painters[id] ?? fallback;

  /// A registry with [painters] added; an id already present is replaced.
  /// This registry is unchanged.
  ChromeIconRegistry withPainters(
    Map<ChromeIconId, ChromeIconPainter> painters,
  ) => ChromeIconRegistry(Map.unmodifiable({..._painters, ...painters}));

  @override
  bool operator ==(Object other) =>
      other is ChromeIconRegistry && mapEquals(other._painters, _painters);

  @override
  int get hashCode => Object.hashAllUnordered(
    _painters.entries.map((e) => Object.hash(e.key, e.value)),
  );
}
