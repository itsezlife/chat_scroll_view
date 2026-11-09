import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/preview/content_preview_item.dart';
import 'package:panel_pages/src/preview/content_preview_menu.dart';
import 'package:panel_pages/src/preview/content_preview_session.dart';
import 'package:panel_shell/panel_shell.dart';

/// The content preview of a catalogue grid: what a page policy (or a sheet's
/// grid) delegates its long press and its context menu to for the cells it
/// previews.
///
/// It answers the policy's questions for a cell: whether it is previewed
/// ([previews]), how long it is held first ([delayOf]), the session that
/// shows it ([begin]), and, for a secondary click, the same items as a
/// context menu ([entriesOf], [perform]). What the grid knows that a cell
/// does not (its pack, whether it is in a recents list) comes from
/// [packOf] and [inRecents].
@immutable
final class CatalogContentPreview {
  /// The preview of a grid drawn through [assets], whose items ask [actions]
  /// and whose open preview [controller] tracks (and whose library it reads).
  const CatalogContentPreview({
    required this.controller,
    required this.assets,
    required this.actions,
    required this.inRecents,
    this.packOf,
  });

  /// The host's handle on the previews.
  final ContentPreviewController controller;

  /// Where the content is drawn from.
  final AssetCacheScope assets;

  /// What the menu's items ask.
  final ContentPreviewActions actions;

  /// Whether a cell is in a recents list.
  final bool Function(CatalogLeafHit hit) inRecents;

  /// The pack of a cell's content, or null; null for no pack anywhere.
  final PackId? Function(CatalogLeafHit hit)? packOf;

  /// The item of [hit], or null for a cell that is not previewed.
  ContentPreviewItem? itemOf(CatalogLeafHit hit) => ContentPreviewItem.ofLeaf(
    hit.leaf,
    pack: packOf?.call(hit),
    inRecents: inRecents(hit),
  );

  /// Whether a long press on [hit] opens a preview.
  bool previews(CatalogLeafHit hit) =>
      ContentPreviewKind.of(hit.leaf.semanticKind) != null;

  /// How long a press by a pointer of [kind] is held before the preview
  /// opens.
  static Duration delayOf(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.mouse
      ? ContentPreviewSession.pointerHoldDelay
      : ContentPreviewSession.touchHoldDelay;

  /// Opens the preview of [hit], following the finger to the cells [leafAt]
  /// names; null for a cell that is not previewed. [hold] is released as the
  /// preview closes.
  ContentPreviewSession? begin(
    BuildContext context,
    CatalogLeafHit hit, {
    required PointerDeviceKind kind,
    CatalogLeafHit? Function(Offset globalPosition)? leafAt,
    PanelPageHold? hold,
  }) {
    final item = itemOf(hit);
    if (item == null) return null;
    return ContentPreviewSession.show(
      context: context,
      item: item,
      assets: assets,
      actions: actions,
      library: controller.library,
      kind: kind,
      hold: hold,
      controller: controller,
      itemAt: switch (leafAt) {
        final leafAt? => (global) => switch (leafAt(global)) {
          final hit? => itemOf(hit),
          null => null,
        },
        null => null,
      },
    );
  }

  /// The preview's items for [hit] as context menu entries; empty for a cell
  /// that is not previewed.
  List<CatalogMenuEntry> entriesOf(CatalogLeafHit hit, PanelStrings strings) =>
      switch (itemOf(hit)) {
        final item? => ContentPreviewMenu.entriesOf(
          item,
          actions,
          strings,
          library: controller.library,
        ),
        null => const [],
      };

  /// Performs the context menu item [itemId] of [hit]; false for an id that
  /// is not one of the preview's.
  bool perform(CatalogLeafHit hit, String itemId) {
    final item = itemOf(hit);
    final action = ContentPreviewAction.byId(itemId);
    if (item == null || action == null) return false;
    ContentPreviewMenu.perform(action, item, actions);
    return true;
  }
}

/// The actions of a preview opened in the panel: each one a request to the
/// panel's host.
///
/// A send is a pick ([PanelPageHost.pick]) of the content's own kind, filed
/// under [recentsKind] (the content's kind when null), from the recents, a
/// collection or [searching]'s results; copy, forget and the library and pack
/// items are the host's requests. No send without sound: the panel's pick
/// has no such variant.
ContentPreviewActions panelPreviewActions(
  PanelPageHost host, {
  SemanticKind? recentsKind,
  bool searching = false,
}) => ContentPreviewActions(
  send: (item) => host.pick(
    item.key,
    kind: item.semanticKind,
    recentsKind: recentsKind,
    source: searching
        ? PickSource.search
        : item.inRecents
        ? PickSource.recents
        : PickSource.collection,
  ),
  copy: (item) => host.requestCopy(item.key, kind: item.semanticKind),
  removeRecent: (item) => host.requestRemoveRecent(
    item.key,
    kind: recentsKind ?? item.semanticKind,
  ),
  editLibrary: host.requestLibraryEdit,
  viewPack: host.requestPack,
);
