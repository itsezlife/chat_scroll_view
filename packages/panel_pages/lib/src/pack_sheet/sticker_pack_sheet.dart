import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_action.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_view.dart';

/// The sticker pack sheet: one pack of stickers or masks, its title, its
/// stickers five to a row, and a button that adds or removes it (the
/// reference mobile client's `StickersAlert`, the desktop client's
/// `StickerSetBox`). Shown with [PackSheet.show].
///
/// Effect-free, as the panel is: it looks the pack up in [packs], reads its
/// install state from [library], and asks the host for everything else.
///
/// - **Loading.** A spinner while [PackSource.peek] answers loading. A pack
///   that is not found, or whose lookup failed, closes the sheet and is
///   reported to [onUnavailable] (the host says "Stickers not found").
/// - **The button.** [PackSheetAction]: "Add 20 stickers" for a pack not
///   installed or archived, "Remove 20 stickers" for an installed one (an
///   official one is archived). A press closes the sheet and asks
///   [onEditsRequested]; the host applies the edit (a removal with its undo
///   window) and shows the feedback.
/// - **Picking.** With [onPick] (given only when the sheet was opened for a
///   composer that can send), a tap on a sticker closes the sheet and hands
///   it to the host to send. Without it a tap does nothing.
/// - **The preview.** [longPress] begins the content preview on a held
///   sticker; without it a press is a tap.
/// - **The menu.** Share and Copy Link, only with [links] and a link for the
///   pack.
///
/// Requires the chrome theme and strings scopes, and a navigator (it closes
/// itself by popping its route).
class StickerPackSheet extends StatelessWidget {
  /// The sheet of the pack [pack].
  const StickerPackSheet({
    required this.pack,
    required this.packs,
    required this.library,
    required this.assets,
    required this.onEditsRequested,
    this.onPick,
    this.onUnavailable,
    this.links,
    this.longPress,
    super.key,
  });

  /// The pack shown.
  final PackId pack;

  /// Where the pack is looked up.
  final PackSource packs;

  /// Read for the pack's install state; the sheet never edits it.
  final ContentLibrary library;

  /// What the grid draws through.
  final AssetCacheScope assets;

  /// Asked to add or remove the pack.
  final PackEditsRequested onEditsRequested;

  /// Asked to send a tapped sticker, or null for a sheet that cannot send.
  final ValueChanged<PackSheetItem>? onPick;

  /// The pack could not be shown; the sheet has closed.
  final ValueChanged<PackLookup>? onUnavailable;

  /// Share and Copy Link, or null for no menu.
  final PackSheetLinks? links;

  /// The preview a held sticker opens, or null for none.
  final PackSheetLongPress? longPress;

  @override
  Widget build(BuildContext context) => PackSheetView(
    packIds: [pack],
    grid: PackSheetGrid.stickers,
    packs: packs,
    library: library,
    assets: assets,
    onEditsRequested: onEditsRequested,
    onPick: onPick,
    onUnavailable: onUnavailable,
    links: links,
    longPress: longPress,
  );
}
