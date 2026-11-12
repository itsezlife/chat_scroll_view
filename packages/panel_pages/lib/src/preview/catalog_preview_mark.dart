import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/preview/content_preview_session.dart';

/// What a catalogue grid draws for a content preview opened over it
/// ([PanelCatalogViewport.leafPreview]): no press or hover on any cell, and
/// the cell the preview shows drawn smaller, following the finger.
///
/// The grid asks its cells through [leafAt], which the opener hands the
/// preview as its own `leafAt`: the cell the finger was last over is the one
/// the preview went to when it changes what it shows. [follow] starts with
/// the session and the cell it opened on; the mark goes when the session
/// closes, or at [clear].
final class CatalogPreviewMark {
  /// A mark over a grid whose cells [leafAt] finds; [onChanged] rebuilds the
  /// grid.
  CatalogPreviewMark({
    required CatalogLeafHit? Function(Offset globalPosition) leafAt,
    required this.onChanged,
  }) : _leafAt = leafAt;

  final CatalogLeafHit? Function(Offset globalPosition) _leafAt;

  /// Called whenever [value] changed.
  final VoidCallback onChanged;

  ContentPreviewSession? _session;
  CatalogLeafHit? _last;
  CatalogLeafHit? _shown;
  CatalogLeafPreview? _value;

  /// What the grid draws: null while no preview is open over it.
  CatalogLeafPreview? get value => _value;

  /// The cell under [globalPosition], remembered as where the finger is.
  CatalogLeafHit? leafAt(Offset globalPosition) =>
      _last = _leafAt(globalPosition);

  /// Marks the cells for [session], opened on [hit]; a session that is not a
  /// content preview (or null) clears the mark.
  void follow(CatalogLongPressSession? session, CatalogLeafHit hit) {
    _unlisten();
    if (session case final ContentPreviewSession session
        when session.isOpen.value) {
      _session = session;
      _shown = _last = hit;
      session.shown.addListener(_onShown);
      session.isOpen.addListener(_onOpen);
      _set(_mark(session));
    } else {
      _set(null);
    }
  }

  /// Takes the mark away and stops following.
  void clear() {
    _unlisten();
    _set(null);
  }

  /// Stops following without telling: for an owner going away.
  void dispose() {
    _unlisten();
    _value = null;
  }

  CatalogLeafPreview _mark(ContentPreviewSession session) => CatalogLeafPreview(
    shrunk: ContentPreviewSession.shrinksCellOf(session.item.kind)
        ? _shown
        : null,
  );

  void _onShown() {
    final session = _session;
    if (session == null) return;
    if (_last case final last? when last.leaf.key == session.item.key) {
      _shown = last;
    }
    _set(_mark(session));
  }

  void _onOpen() {
    if (_session?.isOpen.value ?? false) return;
    clear();
  }

  void _unlisten() {
    _session?.shown.removeListener(_onShown);
    _session?.isOpen.removeListener(_onOpen);
    _session = null;
  }

  void _set(CatalogLeafPreview? value) {
    if (_value == value) return;
    _value = value;
    onChanged();
  }
}
