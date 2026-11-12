import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/media_panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';

/// Warms the texture pool for the panel page that plays (ADR 043, "Pool"):
/// when the panel opens on it, and when it is selected in the open panel.
///
/// A lease never creates a texture, so without this the first screen of
/// stickers or GIFs would wait on its page slots for a turn and create its
/// textures while the user already scrolls. The pool still waits with each
/// creation while a surface scrolls.
final class PanelTextureWarmer {
  /// Warms [pool] for the pages of [shell] that
  /// [MediaPanelPages.playingLeaves] lists, at [devicePixelRatio].
  PanelTextureWarmer({
    required PanelShellController shell,
    required FrameTexturePool pool,
    required double devicePixelRatio,
  }) : _shell = shell,
       _pool = pool,
       _devicePixelRatio = devicePixelRatio {
    shell.visible.addListener(_warm);
    shell.selectedPageId.addListener(_warm);
    _warm();
  }

  final PanelShellController _shell;
  final FrameTexturePool _pool;
  final double _devicePixelRatio;
  bool _disposed = false;

  void _warm() {
    if (_disposed || !_shell.visible.value) return;
    final leaves = MediaPanelPages.playingLeaves[_shell.selectedPageId.value];
    if (leaves == null) return;
    final pixels = (leaves.extent * _devicePixelRatio).ceil();
    final sizeClass = _pool.classOf(pixels, pixels);
    if (sizeClass == null) return;
    unawaited(_pool.warm(sizeClass, leaves.perScreen));
  }

  /// Stops warming; what was asked of the pool goes on. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _shell.visible.removeListener(_warm);
    _shell.selectedPageId.removeListener(_warm);
  }
}
