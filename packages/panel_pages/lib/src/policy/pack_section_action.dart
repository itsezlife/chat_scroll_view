import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_shell/panel_shell.dart';

/// The cross at the end of a section header: the recents' clear button and,
/// under a pointer, the remove button of a pack the user installed.
abstract final class PackSectionAction {
  /// The id the remove button of a pack's header reports.
  static const String removePackActionId = 'remove-pack';

  /// Whether [collection] is a pack the user can remove from the header: a
  /// set the source says is installed.
  static bool removable(Collection collection) =>
      collection.id is CollectionId$Set &&
      collection.metadata.flags.contains(CollectionFlags.installed);

  /// The remove button of [collection]'s header under [arrangement], or null
  /// where it has none: only under a desktop's pointer (the web's headers
  /// have none: only the recents carry a cross there), and only on a
  /// [removable] pack.
  static CatalogSectionAction? removeOf(
    Collection collection,
    PanelStrings strings,
    PanelArrangement arrangement, {
    bool web = kIsWeb,
  }) => arrangement == PanelArrangement.pointer && !web && removable(collection)
      ? CatalogSectionAction(
          id: removePackActionId,
          painter: paintCross,
          semanticLabel: strings.removePackAction,
        )
      : null;

  /// Asks [host] to remove the pack of [collection] (a set), of [kind]; the
  /// host confirms it as its platform does. Nothing for any other collection.
  static void requestRemove(
    Collection collection,
    PackKind kind,
    PanelPageHost host,
  ) {
    if (collection.id case CollectionId$Set(:final id)) {
      host.requestLibraryEdit(LibraryEdit.removePack(PackId(id), kind));
    }
  }

  /// Two strokes crossing, in the header's colour. One path, so a
  /// translucent colour covers the crossing once.
  static void paintCross(Canvas canvas, Rect box, Color color) {
    final unit = box.width / 24;
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * unit
      ..strokeCap = StrokeCap.round;
    final near = box.left + 7.5 * unit;
    final far = box.left + 16.5 * unit;
    final top = box.top + 7.5 * unit;
    final bottom = box.top + 16.5 * unit;
    final cross = Path()
      ..moveTo(near, top)
      ..lineTo(far, bottom)
      ..moveTo(far, top)
      ..lineTo(near, bottom);
    canvas.drawPath(cross, pen);
  }
}
