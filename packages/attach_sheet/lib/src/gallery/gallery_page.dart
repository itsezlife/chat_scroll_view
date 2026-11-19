import 'dart:async';

import 'package:attach_sheet/src/gallery/attach_picker_selection.dart';
import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:attach_sheet/src/panel/attach_panel.dart';
import 'package:attach_sheet/src/panel/attach_send_controller.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_ui/mpx_ui.dart';

/// The stock **Gallery page**: `mpx_ui`'s library grid over the device
/// library, counting into the open's one attach selection.
///
/// Library picks share their order numbers with files and captures; a pick
/// past the cap or of a kind the limits forbid is refused (its cell dimmed)
/// and raised to the host as an attach interaction. The header carries the
/// overflow menu. The camera slot is the host's [cameraSlot] (the live
/// preview over its camera session); without one the grid has no camera
/// cell.
///
/// Thumbnails come through the `AssetCacheProvider` above the sheet, whose
/// fetcher sends library keys to `LibraryFetcher(library)`.
abstract final class GalleryPage {
  /// The Gallery page over [library], labelled [label] with [icon].
  static AttachPage create({
    required MediaLibrary library,
    required String label,
    required Widget icon,
    CameraSlotBuilder? cameraSlot,
    AttachPagePermission? permission,
  }) => AttachPage(
    id: AttachPageId.gallery,
    label: label,
    icon: icon,
    permission: permission,
    builder: (context, scope) => GalleryView(
      library: library,
      panel: scope.panel,
      controller: scope.scrollController,
      active: scope.isActive,
      cameraSlot: cameraSlot,
      onHeader: (header) => scope.headerItems = header,
    ),
  );
}

/// The grid of the Gallery page, also shown on its own (the Files page's
/// "Choose from gallery").
class GalleryView extends StatefulWidget {
  /// A grid over [library] picking into [panel]'s selection.
  const GalleryView({
    required this.library,
    required this.panel,
    this.controller,
    this.active,
    this.cameraSlot,
    this.onHeader,
    super.key,
  });

  /// The device library.
  final MediaLibrary library;

  /// The panel's state: its selection, its policy, its host.
  final AttachSendController panel;

  /// The grid's scroll controller (the sheet's, so a drag moves the sheet).
  final ScrollController? controller;

  /// Whether the view is the one shown; the camera slot pauses while not.
  final ValueListenable<bool>? active;

  /// The camera cell's content; null for none.
  final CameraSlotBuilder? cameraSlot;

  /// Called with the view's header items (the overflow menu).
  final ValueChanged<Widget?>? onHeader;

  @override
  State<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<GalleryView> {
  late final AttachPickerSelection _$picker = AttachPickerSelection(
    selection: widget.panel.selection,
    source: widget.library,
    onRefused: widget.panel.host.interaction,
  );
  LibraryAlbum? _album;

  @override
  void initState() {
    super.initState();
    widget.library.access.addListener(_accessChanged);
    unawaited(_load());
    if (widget.onHeader case final onHeader?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onHeader(AttachOverflowButton(controller: widget.panel));
      });
    }
  }

  @override
  void dispose() {
    widget.library.access.removeListener(_accessChanged);
    super.dispose();
  }

  void _accessChanged() => unawaited(_load());

  Future<void> _load() async {
    var access = widget.library.access.value;
    if (access == LibraryAccess.notDetermined) {
      access = await widget.library.requestAccess();
    }
    if (!access.canRead) {
      if (mounted) setState(() => _album = null);
      return;
    }
    final albums = await widget.library.albums();
    if (!mounted) return;
    setState(() => _album = albums.isEmpty ? null : albums.first);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.attachOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final tokens = ChromeThemeScope.attachOf(context);
    final album = _album;
    if (album == null) {
      return _NoAccess(
        library: widget.library,
        strings: strings,
        palette: palette,
      );
    }
    LibraryGrid grid({bool active = true}) => LibraryGrid(
      key: const ValueKey('attach-gallery-grid'),
      library: _$picker.library,
      album: album,
      selection: _$picker,
      labels: LibraryGridLabels(
        photo: strings.libraryPhoto,
        video: strings.libraryVideo,
        open: strings.libraryOpen,
        select: strings.librarySelect,
        gif: strings.libraryGif,
      ),
      policy: widget.panel.policy.libraryGrid,
      tokens: LibraryGridTokens(
        background: tokens.background,
        cameraSlotBackground: tokens.background,
        checkFill: palette.accent,
      ),
      cameraSlotBuilder: widget.cameraSlot,
      controller: widget.controller,
      active: active,
    );
    return switch (widget.active) {
      final active? => ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (context, shown, _) => grid(active: shown),
      ),
      null => grid(),
    };
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess({
    required this.library,
    required this.strings,
    required this.palette,
  });

  final MediaLibrary library;
  final AttachStrings strings;
  final ChromePalette palette;

  @override
  Widget build(BuildContext context) {
    final access = library.access.value;
    final denied =
        access == LibraryAccess.denied || access == LibraryAccess.restricted;
    return Center(
      key: const ValueKey('attach-gallery-no-access'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            access.canRead ? strings.libraryEmpty : strings.libraryNoAccess,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.onSurfaceMuted, fontSize: 15),
          ),
          if (!access.canRead) ...[
            const SizedBox(height: 12),
            GestureDetector(
              key: const ValueKey('attach-gallery-allow'),
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(
                denied ? library.openSettings() : library.requestAccess(),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  strings.libraryAllowAccess,
                  style: TextStyle(color: palette.accent, fontSize: 15),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
