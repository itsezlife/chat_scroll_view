import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/files/intake_items.dart';
import 'package:attach_sheet/src/gallery/attach_picker_selection.dart';
import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:attach_sheet/src/panel/attach_interaction.dart';
import 'package:attach_sheet/src/panel/attach_panel.dart';
import 'package:attach_sheet/src/panel/attach_send_controller.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_core/mpx_core.dart' show MediaKey;
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_player/mpx_player.dart' show PlayerPool;
import 'package:mpx_ui/mpx_ui.dart';

/// The camera cell's wiring: the host's camera sessions, where captures are
/// written, and the system camera for a long press (Android) or when the
/// session cannot open.
@immutable
final class GalleryCamera {
  /// A camera over [sessions], writing into [outputDirectory].
  const GalleryCamera({
    required this.sessions,
    required this.outputDirectory,
    this.systemCamera,
  });

  /// Opens the live camera.
  final CameraSessions sessions;

  /// Where the capture surface writes its photos and videos.
  final String outputDirectory;

  /// The system camera (`FileIntake.captureWithSystemCamera`); null for
  /// none.
  final FileIntake? systemCamera;
}

/// The stock **Gallery page**: `mpx_ui`'s library picker (album switcher,
/// access states, the grid, the picker-mode viewer) over the device library,
/// counting into the open's one attach selection.
///
/// Library picks share their order numbers with files and captures; a pick
/// past the cap or of a kind the limits forbid is refused (its cell dimmed)
/// and raised to the host as an attach interaction. The header carries the
/// album switcher and the overflow menu. With a [camera] the first cell is
/// the live preview: a tap opens the capture surface, a long press (Android)
/// or a session that cannot open the system camera; captures join the
/// selection first. The viewer's bottom slot is the panel's caption and
/// Send; Send with nothing checked sends the item shown. The viewer's videos
/// play on [players] (the host answers library keys with
/// `LibraryPlayerSources.of`); without them they show their poster.
///
/// A tap on the panel's count swaps the grid for the **selected-items
/// preview** (`PickerSelectionPreview`): the picks in their order, a tap on
/// a number deselects, a tap on a picture opens the viewer over the picks,
/// and a long press drags an item to another place in the order. The count
/// again, or back, returns to the grid, as does emptying the selection.
///
/// Thumbnails come through the `AssetCacheProvider` above the sheet, whose
/// fetcher sends library keys to `LibraryFetcher(library)`.
abstract final class GalleryPage {
  /// The Gallery page over [library], labelled [label] with [icon].
  static AttachPage create({
    required MediaLibrary library,
    required String label,
    required Widget icon,
    GalleryCamera? camera,
    PlayerPool? players,
    AttachPagePermission? permission,
  }) => AttachPage(
    id: AttachPageId.gallery,
    label: label,
    icon: icon,
    permission: permission,
    builder: (context, scope) {
      // Back from the selected-items preview returns to the grid.
      scope.dismissGuard = () async {
        final previewing = scope.panel.previewingSelection;
        if (!previewing.value) return true;
        previewing.value = false;
        return false;
      };
      return GalleryView(
        library: library,
        panel: scope.panel,
        controller: scope.scrollController,
        active: scope.isActive,
        camera: camera,
        players: players,
      );
    },
  );
}

/// The picker of the Gallery page, also shown on its own (the Files page's
/// "Choose from gallery").
class GalleryView extends StatefulWidget {
  /// A picker over [library] picking into [panel]'s selection.
  const GalleryView({
    required this.library,
    required this.panel,
    this.controller,
    this.active,
    this.camera,
    this.players,
    this.showsOverflow = true,
    super.key,
  });

  /// The device library.
  final MediaLibrary library;

  /// The panel's state: its selection, its policy, its host.
  final AttachSendController panel;

  /// The grid's scroll controller (the sheet's, so a drag moves the sheet).
  final ScrollController? controller;

  /// Whether the view is the one shown; the camera pauses while not.
  final ValueListenable<bool>? active;

  /// The camera cell's wiring; null for no camera cell.
  final GalleryCamera? camera;

  /// The players the viewer's videos play on; null shows their posters.
  final PlayerPool? players;

  /// Whether the header carries the overflow menu.
  final bool showsOverflow;

  @override
  State<GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<GalleryView> {
  late final AttachPickerSelection _$picker = AttachPickerSelection(
    selection: widget.panel.selection,
    source: widget.library,
    onRefused: widget.panel.host.interaction,
  );
  final IntakeItems _$captures = IntakeItems();
  CameraSession? _$session;
  bool _cameraDenied = false;
  final GlobalKey _$slot = GlobalKey();

  AttachSelection get _selection => widget.panel.selection;

  bool get _mediaAllowed =>
      _selection.limits.allows(AttachKind.photo) ||
      _selection.limits.allows(AttachKind.video);

  CaptureKinds? get _kinds => switch ((
    _selection.limits.allows(AttachKind.photo),
    _selection.limits.allows(AttachKind.video),
  )) {
    (true, true) => CaptureKinds.photoAndVideo,
    (true, false) => CaptureKinds.photo,
    (false, true) => CaptureKinds.video,
    (false, false) => null,
  };

  @override
  void initState() {
    super.initState();
    widget.panel.hostSelectionPreview(present: true);
    if (widget.camera case final camera? when _kinds != null) {
      unawaited(_openCamera(camera));
    }
  }

  Future<void> _openCamera(GalleryCamera camera) async {
    try {
      final session = await camera.sessions.open(frameRateCap: 30);
      if (!mounted) {
        unawaited(session.dispose());
        return;
      }
      setState(() {
        _$session = session;
        _cameraDenied = session.value.value.state == CameraSessionState.denied;
      });
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'attach_sheet',
          context: ErrorDescription('opening the gallery camera'),
        ),
      );
      if (mounted) setState(() => _cameraDenied = true);
    }
  }

  @override
  void dispose() {
    widget.panel.hostSelectionPreview(present: false);
    unawaited(_$session?.dispose());
    super.dispose();
  }

  /// A capture joins the selection ahead of everything picked.
  void _captured(String path, {required bool isVideo, String? mimeType}) {
    final item = AttachItem(
      id: AttachItemId('captured:$path'),
      source: AttachSource.captured(path),
      kind: isVideo ? AttachKind.video : AttachKind.photo,
      facts: AttachFacts(mimeType: mimeType),
    );
    if (_selection.selectFirst(item) case AttachToggle$Refused(:final reason)) {
      widget.panel.host.interaction(AttachInteraction.refused(reason));
    }
  }

  Future<void> _systemCamera() async {
    final intake = widget.camera?.systemCamera;
    final kinds = _kinds;
    if (intake == null || kinds == null || !intake.canCaptureWithSystemCamera) {
      return;
    }
    final file = await intake.captureWithSystemCamera(
      kinds.photos ? IntakeCaptureKind.photo : IntakeCaptureKind.video,
    );
    if (file == null || !mounted) return;
    final item = _$captures.itemOf(file, asMedia: true);
    _captured(
      switch (file.source) {
        IntakeSource$Path(:final path) => path,
        IntakeSource$Blob() => item.id,
      },
      isVideo: item.kind == AttachKind.video,
      mimeType: file.mimeType,
    );
  }

  Future<void> _openCaptureSurface() async {
    final camera = widget.camera;
    final session = _$session;
    final kinds = _kinds;
    if (camera == null || kinds == null) return;
    if (session == null || !session.value.value.isAvailable) {
      return _systemCamera();
    }
    final strings = ChromeStringsScope.attachOf(context);
    final box = _$slot.currentContext?.findRenderObject() as RenderBox?;
    await CameraCaptureSurface.show(
      context,
      session: session,
      labels: CaptureSurfaceLabels(
        close: strings.captureClose,
        shutter: strings.captureShutter,
        switchCamera: strings.captureSwitchCamera,
        flash: strings.captureFlash,
      ),
      outputDirectory: camera.outputDirectory,
      kinds: kinds,
      from: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      onCaptured: (shot) => _captured(shot.output.path, isVideo: shot.isVideo),
    );
  }

  Widget _cameraSlot(
    BuildContext context,
    ValueListenable<CameraSlotSignals> signals,
  ) {
    final session = _$session;
    if (session == null) return SizedBox.expand(key: _$slot);
    return ValueListenableBuilder<CameraSlotSignals>(
      key: _$slot,
      valueListenable: signals,
      builder: (context, value, _) => CameraSlotPreview(
        session: session,
        paused: value.shouldPause,
        // Reported while the preview builds: mark the camera denied after
        // the frame.
        onUnavailable: (_) => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_cameraDenied) setState(() => _cameraDenied = true);
        }),
      ),
    );
  }

  /// The viewer's bottom slot: the panel's caption and Send; Send with
  /// nothing selected selects the item shown first.
  Widget _viewerSlot(BuildContext context, PickerViewerItem item) =>
      AttachCaptionBar(
        controller: widget.panel,
        beforeSend: () {
          if (_selection.isNotEmpty) return;
          if (item.asset case final asset?) {
            _selection.toggle(AttachPickerSelection.itemOf(asset));
          }
        },
      );

  /// Opens the viewer over the picks, at the [index]th.
  Future<void> _openSelected(MediaKey key, int index) async {
    final album = _$picker.selectedAlbumNow;
    if (index >= album.count) return;
    final pages = LibraryPages(library: _$picker.library, album: album);
    final source = LibraryGallerySource(pages);
    try {
      await PickerViewer.show(
        context,
        source: source,
        initialIndex: index,
        selection: _$picker,
        labels: _labels(ChromeStringsScope.attachOf(context)),
        gridPolicy: widget.panel.policy.libraryGrid,
        tokens: _tokens(context),
        players: widget.players,
        bottomBuilder: _viewerSlot,
      );
    } finally {
      source.dispose();
      pages.dispose();
    }
  }

  static LibraryGridLabels _labels(AttachStrings strings) => LibraryGridLabels(
    photo: strings.libraryPhoto,
    video: strings.libraryVideo,
    open: strings.libraryOpen,
    select: strings.librarySelect,
    gif: strings.libraryGif,
    camera: strings.libraryCamera,
  );

  static LibraryGridTokens _tokens(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final tokens = ChromeThemeScope.attachOf(context);
    return LibraryGridTokens(
      background: tokens.background,
      cameraSlotBackground: tokens.background,
      checkFill: palette.accent,
    );
  }

  Widget _preview(BuildContext context) => ColoredBox(
    color: ChromeThemeScope.attachOf(context).background,
    child: PickerSelectionPreview(
      key: const ValueKey('attach-gallery-preview'),
      selection: _$picker,
      labels: _labels(ChromeStringsScope.attachOf(context)),
      policy: widget.panel.policy.libraryGrid,
      tokens: _tokens(context),
      controller: widget.controller,
      onOpen: (key, index) => unawaited(_openSelected(key, index)),
      onReorder: _$picker.move,
      onRefused: (_, _) {},
    ),
  );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.panel.previewingSelection,
    builder: (context, previewing, _) =>
        previewing ? _preview(context) : _grid(context),
  );

  Widget _grid(BuildContext context) {
    final strings = ChromeStringsScope.attachOf(context);
    final camera = widget.camera;
    final android =
        widget.panel.policy.libraryGrid == LibraryGridPolicy.$Android;
    Widget picker({bool active = true}) => LibraryPicker(
      key: const ValueKey('attach-gallery-picker'),
      library: _$picker.library,
      selection: _$picker,
      labels: _labels(strings),
      stateLabels: LibraryPickerLabels(
        allMedia: strings.albumAllMedia,
        allPhotos: strings.albumAllPhotos,
        allVideos: strings.albumAllVideos,
        cameraAlbum: strings.albumCamera,
        favourites: strings.albumFavourites,
        empty: strings.libraryEmpty,
        deniedTitle: strings.libraryDeniedTitle,
        deniedText: strings.libraryNoAccess,
        allowAccess: strings.libraryAllowAccess,
        openSettings: strings.libraryOpenSettings,
        camera: strings.libraryCamera,
        restricted: strings.libraryRestricted,
        limitedText: strings.libraryLimited,
        manage: strings.libraryManage,
        selectMore: strings.librarySelectMore,
        changeSettings: strings.libraryChangeSettings,
        partialText: strings.libraryPartial,
        cameraDeniedText: strings.libraryCameraDenied,
      ),
      policy: widget.panel.policy.libraryGrid,
      tokens: _tokens(context),
      players: widget.players,
      // The sheet's scroll controller: a drag on the grid raises the sheet
      // to its top before the grid scrolls, and at the grid's top lowers or
      // dismisses it, in one gesture.
      controller: widget.controller,
      mediaAllowed: _mediaAllowed,
      notAllowedText: strings.mediaNotAllowed,
      cameraDenied: _cameraDenied,
      cameraSlotBuilder: camera == null || _kinds == null ? null : _cameraSlot,
      onCameraTap: camera == null
          ? null
          : () => unawaited(_openCaptureSurface()),
      onCameraLongPress: camera == null || !android
          ? null
          : () => unawaited(_systemCamera()),
      onCamera: camera == null ? null : () => unawaited(_systemCamera()),
      viewerBottomBuilder: _viewerSlot,
      headerBuilder: (context, switcher) => Row(
        children: [
          Expanded(child: switcher),
          if (widget.showsOverflow)
            AttachOverflowButton(controller: widget.panel),
        ],
      ),
      active: active,
    );
    return switch (widget.active) {
      final active? => ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (context, shown, _) => picker(active: shown),
      ),
      null => picker(),
    };
  }
}
