import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_action.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_view.dart';

/// The emoji pack sheet: one pack of custom emoji, or several (the reference
/// mobile client's `EmojiPacksAlert`). Shown with [PackSheet.show].
///
/// Effect-free like [StickerPackSheet]: it looks [packIds] up in [packs],
/// reads their install states from [library], and asks the host for the rest.
///
/// - **One pack.** Its title, its emoji in square columns at least 45 wide,
///   and the button: "Add 32 emoji" or "Remove 32 emoji".
/// - **Several packs.** Each under a header with its title and its own Add
///   or Remove button, two rows of eight at most; a tap on an emoji shows
///   that pack alone. The button adds the packs not added yet ("Add 2 emoji
///   packs"), or removes them all once all are. A header's button leaves the
///   sheet up; the bottom one closes it.
/// - **Picking.** With [onPick] (the sheet was opened for a composer), a tap
///   on an emoji of one pack closes the sheet and hands it to the host to
///   insert.
/// - **No preview.** An emoji pack's grid is never previewed (the
///   reference's `ContentPreviewViewer.can()` is false for one).
/// - **The preview emoji.** With [previewEmoji] (the emoji the user tapped in
///   a message), that emoji is drawn large above the card and moves with it,
///   as the reference's `setPreviewEmoji` does; it fades out for good once
///   the user scrolls the grid, the sheet closes, or there is no room for it
///   above the card. Touch only: a box under a pointer has none.
/// - **Unavailable.** A pack not found, or whose lookup failed, closes the
///   sheet and is reported to [onUnavailable] ("Emoji pack not found.").
///
/// [StickerPackSheet]: package:panel_pages/src/pack_sheet/sticker_pack_sheet.dart
class EmojiPackSheet extends StatelessWidget {
  /// The sheet of [packIds]: one pack, or several.
  const EmojiPackSheet({
    required this.packIds,
    required this.packs,
    required this.library,
    required this.assets,
    required this.onEditsRequested,
    this.onPick,
    this.onUnavailable,
    this.links,
    this.previewEmoji,
    super.key,
  }) : assert(packIds.length > 0, 'A pack sheet shows at least one pack.');

  /// The packs shown, in order, without repeats.
  final List<PackId> packIds;

  /// Where the packs are looked up.
  final PackSource packs;

  /// Read for the install states; the sheet never edits it.
  final ContentLibrary library;

  /// What the grid draws through.
  final AssetCacheScope assets;

  /// Asked to add or remove packs.
  final PackEditsRequested onEditsRequested;

  /// Asked to insert a tapped emoji, or null for a sheet with no composer.
  final ValueChanged<PackSheetItem>? onPick;

  /// A pack could not be shown; the sheet has closed.
  final ValueChanged<PackLookup>? onUnavailable;

  /// Share and Copy Link of a single pack, or null for no menu.
  final PackSheetLinks? links;

  /// The emoji to show above the sheet (the one tapped to open it), or null.
  final ContentKey? previewEmoji;

  @override
  Widget build(BuildContext context) => PackSheetView(
    packIds: packIds,
    grid: packIds.length == 1
        ? PackSheetGrid.emoji
        : PackSheetGrid.severalEmoji,
    packs: packs,
    library: library,
    assets: assets,
    onEditsRequested: onEditsRequested,
    onPick: onPick,
    onUnavailable: onUnavailable,
    links: links,
    previewEmoji: previewEmoji,
  );
}
