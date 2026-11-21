import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/debug/attach_log.dart';
import 'package:attach_sheet/src/files/intake_items.dart';
import 'package:attach_sheet/src/gallery/attach_picker_selection.dart';
import 'package:attach_sheet/src/gallery/gallery_captures.dart';
import 'package:attach_sheet/src/gallery/gallery_fast_scroll.dart';
import 'package:attach_sheet/src/gallery/gallery_strip_album.dart';
import 'package:attach_sheet/src/host/attach_caption_dock.dart';
import 'package:attach_sheet/src/page/attach_page.dart';
import 'package:attach_sheet/src/panel/attach_interaction.dart';
import 'package:attach_sheet/src/panel/attach_panel.dart';
import 'package:attach_sheet/src/panel/attach_send_controller.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' show RichText;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_core/mpx_core.dart' show MediaKey, MediaKey$Local;
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_player/mpx_player.dart' show PlayerPool;
import 'package:mpx_ui/mpx_ui.dart';

/// The camera cell's wiring: the host's camera sessions, where captures are
/// written and then kept, and the system camera for a long press (Android)
/// or when the session cannot open.
@immutable
final class GalleryCamera {
  /// A camera over [sessions], writing into [outputDirectory] and moving
  /// each shot into [cache].
  const GalleryCamera({
    required this.sessions,
    required this.outputDirectory,
    required this.cache,
    this.systemCamera,
  });

  /// Where each shot is kept under a `MediaKey.local`: the bytes store the
  /// host's asset cache reads (for the grid's and the viewer's thumbnails)
  /// and its players read (for a captured video).
  final CaptureCache cache;

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
    String? viewerTitle,
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
        viewerTitle: viewerTitle,
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
    this.viewerTitle,
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

  /// The viewer's title: the name of the chat the media goes to.
  final String? viewerTitle;

  /// The viewer's info line under the title for [asset]: for a video the
  /// device can compress, what is sent at the default step of the platform's
  /// [policy] (`WxH, m:ss, ~size`); nothing for a photo, or for a video that
  /// goes as it is.
  static String? viewerInfoOf(LibraryAsset asset, {PreparationPolicy? policy}) {
    if (asset.kind != LibraryAssetKind.video) return null;
    final dimensions = asset.dimensions;
    final duration = asset.duration;
    if (dimensions == null || duration == null) return null;
    final source = SourceVideo(
      dimensions: dimensions,
      duration: duration,
      codec: SourceCodec.other,
    );
    final rules =
        policy ?? PreparationPolicy.forPlatform(defaultTargetPlatform);
    final preset = rules.defaultPreset(source, byteSize: asset.byteSize);
    if (preset == null) return null;
    final plan = preset.planFor(source);
    final bits =
        (plan.videoBitrate + plan.audioBitrate) *
        duration.inMilliseconds /
        1000;
    return [
      '${plan.size.width}x${plan.size.height}',
      LibraryGridLabels.formatDuration(duration),
      '~${PickerViewer.formatBytes((bits / 8).round())}',
    ].join(', ');
  }

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
    captures: _$shots,
  );
  final IntakeItems _$intake = IntakeItems();

  // The camera's shots of this open: the grid's captures, selected last,
  // released if the sheet goes without sending them.
  late final GalleryCaptures? _$shots = switch (widget.camera) {
    final camera? => GalleryCaptures(
      selection: widget.panel.selection,
      release: (key) => unawaited(camera.cache.release(key)),
      onRefused: widget.panel.host.interaction,
      keepPoster: (shot) => _keepPoster(camera.cache, shot),
    ),
    null => null,
  };
  CameraSession? _$session;
  bool _cameraDenied = false;
  final GlobalKey<LibraryPickerState> _$pickerKey = GlobalKey();
  // Whether the capture surface is shown: a viewer opened now is the
  // camera's (its caption leads with add-photo, and back may take the shot
  // back).
  bool _surfaceOpen = false;
  final GlobalKey _$slot = GlobalKey();

  // Where the focus rests in the sheet's route when no field holds it (the
  // viewer gone, its caption unfocused).
  final FocusNode _restFocus = FocusNode(
    debugLabel: 'Gallery',
    skipTraversal: true,
  );
  final LibraryGridLookup _$lookup = LibraryGridLookup();
  ScrollController? _$ownController;

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
    _restFocus.dispose();
    widget.panel.hostSelectionPreview(present: false);
    _$lookup.dispose();
    _$ownController?.dispose();
    unawaited(_$session?.dispose());
    // Shots the sheet did not send go with it.
    _$shots
      ?..discard(
        sent: {
          for (final item in widget.panel.sent?.items ?? const <AttachItem>[])
            item.id,
        },
      )
      ..dispose();
    super.dispose();
  }

  /// A system camera capture joins the selection ahead of everything
  /// picked, as a file.
  void _captured(String path, {required bool isVideo, String? mimeType}) {
    final item = AttachItem(
      id: AttachItemId('captured:$path'),
      source: AttachSource.file(path),
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
    final item = _$intake.itemOf(file, asMedia: true);
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
    _surfaceOpen = true;
    _$shots?.cameraOpened();
    try {
      await _showSurface(camera, session, kinds, strings, box);
    } finally {
      _surfaceOpen = false;
      _$shots?.cameraClosed();
    }
  }

  Future<void> _showSurface(
    GalleryCamera camera,
    CameraSession session,
    CaptureKinds kinds,
    AttachStrings strings,
    RenderBox? box,
  ) async {
    // The strip lists the grid's album after the shots, as the grid does.
    final album = switch (_$pickerKey.currentState?.pages) {
      final pages? => GalleryStripAlbum(pages),
      null => null,
    };
    try {
      await _showSurfaceWith(camera, session, kinds, strings, box, album);
    } finally {
      album?.dispose();
    }
  }

  Future<void> _showSurfaceWith(
    GalleryCamera camera,
    CameraSession session,
    CaptureKinds kinds,
    AttachStrings strings,
    RenderBox? box,
    GalleryStripAlbum? album,
  ) async {
    final shots = _$shots;
    await CameraCaptureSurface.show(
      context,
      session: session,
      labels: CaptureSurfaceLabels(
        close: strings.captureClose,
        shutter: strings.captureShutter,
        switchCamera: strings.captureSwitchCamera,
        flash: strings.captureFlash,
        videoMode: strings.captureVideoMode,
        photoMode: strings.capturePhotoMode,
        shotsCount: (photos, videos) => shotsCount(strings, photos, videos),
      ),
      outputDirectory: camera.outputDirectory,
      kinds: kinds,
      cache: camera.cache,
      from: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      // The platform's surface: Android's shutter, or iOS's modes, lenses
      // and results strip.
      policy: CaptureSurfacePolicy.forPlatform(Theme.of(context).platform),
      onCaptured: (shot) => shots?.add(shot),
      // The strip and the counter show the shots this open keeps; the
      // counter opens the viewer over them, at the newest.
      shots: shots?.shots,
      onShotsTap: shots == null ? null : _openCaptures,
      // The strip's own cells, numbered by the selection; a tap toggles.
      shotOrder: (shot) => switch (shot.key) {
        final key? => _$picker.orderOf(key),
        null => null,
      },
      onShotToggle: (shot) {
        if (shot.key case final key?) _$picker.toggle(key);
      },
      shotSelection: _$picker,
      gallery: album,
      galleryOrder: _$picker.orderOf,
      onGalleryToggle: (key) => _$picker.toggle(key),
      onShotRemoved: shots?.remove,
      // A hold where videos may not be sent, or one whose microphone was
      // refused: the host says so.
      onVideoRefused: (refusal) => widget.panel.host.interaction(
        AttachInteraction.videoRefused(switch (refusal) {
          CaptureVideoRefusal.notAllowed => AttachVideoRefusal.notAllowed,
          CaptureVideoRefusal.microphone => AttachVideoRefusal.microphone,
        }),
      ),
    );
  }

  /// The shots counter's words: so many photos, videos, or media of both,
  /// upper-cased.
  @visibleForTesting
  static String shotsCount(AttachStrings strings, int photos, int videos) {
    final n = photos + videos;
    final words = switch ((photos, videos)) {
      (_, 0) => strings.capturedPhotos(n),
      (0, _) => strings.capturedVideos(n),
      _ => strings.capturedMedia(n),
    };
    return words.toUpperCase();
  }

  // The shots counter: the viewer over the shots, at the newest; back from
  // it may take a lone shot back.
  void _openCaptures() {
    final picker = _$pickerKey.currentState;
    if (picker == null) return;
    _$shots?.viewerOpenedFromCamera();
    unawaited(picker.openCaptures());
  }

  // A viewer closed: the camera's may take its lone shot back.
  void _viewerClosed() {
    if (_surfaceOpen) _$shots?.viewerClosed();
  }

  // A recording's poster (the first frame the platform wrote beside it)
  // kept in the capture cache as a still under a key of its own: the
  // grid's cell draws it. The poster's file stays where the camera wrote it
  // (the surface's strip reads it too).
  static Future<MediaKey$Local?> _keepPoster(
    CaptureCache cache,
    CameraShot shot,
  ) async {
    final path = shot.output.posterPath;
    if (path == null) return null;
    final key = cache.mintKey();
    await cache.put(
      key,
      CaptureOutput(
        path: path,
        size: await File(path).length(),
        duration: Duration.zero,
        dimensions: shot.output.dimensions,
        headerRewritten: false,
      ),
      deleteSource: false,
    );
    return key;
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
  ///
  /// Over the media it is the floating caption bar in the night palette,
  /// on its own dock from the host (the keyboard's place and the panel), as
  /// the sheet's caption is. The viewer stands the slot on the screen's
  /// bottom and never lifts it (`bottomSlotHoldsKeyboard`): the dock's
  /// place holds the keyboard and the safe area.
  Widget _viewerSlot(BuildContext context, PickerViewerItem item) =>
      ChromeThemeScope(
        palette: const ChromePalette.dark(),
        child: ChromeTextRoot(
          child: _ViewerCaption(
            key: const ValueKey('attach-viewer-slot'),
            controller: widget.panel,
            item: switch (item.asset) {
              final asset? => AttachPickerSelection.itemOf(asset),
              null => null,
            },
            sheetRest: _restFocus,
            chromeShown: item.chromeShown,
            // The camera's viewer leads its caption with add-photo, back to
            // the camera for another shot, unless one item is all it takes.
            addMore: switch (_$shots) {
              final shots?
                  when _surfaceOpen && !_selection.limits.singleSelect =>
                () {
                  shots.addMore();
                  unawaited(item.close());
                },
              _ => null,
            },
            beforeSend: () {
              if (_selection.isNotEmpty) return;
              if (item.asset case final asset?) {
                _selection.toggle(AttachPickerSelection.itemOf(asset));
              }
            },
          ),
        ),
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
        bottomSlotHoldsKeyboard: true,
        onReorder: _$picker.move,
        assetOf: _$picker.assetOf,
        title: widget.viewerTitle,
        subtitleOf: GalleryView.viewerInfoOf,
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
    highQuality: strings.libraryHighQuality,
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
      // The marks the grid shows on the item (a video's duration, HD).
      assetOf: _$picker.assetOf,
      onRefused: (_, _) {},
    ),
  );

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _restFocus,
    child: ListenableBuilder(
      listenable: Listenable.merge([
        widget.panel.previewingSelection,
        widget.panel.options,
      ]),
      builder: (context, _) => widget.panel.previewingSelection.value
          ? _preview(context)
          : _grid(context),
    ),
  );

  Widget _grid(BuildContext context) {
    final strings = ChromeStringsScope.attachOf(context);
    final camera = widget.camera;
    final android =
        widget.panel.policy.libraryGrid == LibraryGridPolicy.$Android;
    // The sheet's, so a drag moves the sheet; on its own, the ambient one
    // or the view's.
    final controller =
        widget.controller ??
        PrimaryScrollController.maybeOf(context) ??
        (_$ownController ??= ScrollController());
    Widget picker({bool active = true}) => LibraryPicker(
      key: _$pickerKey,
      library: _$picker.library,
      selection: _$picker,
      // The camera's shots, ahead of the library; the first opens the
      // viewer on it.
      captures: _$shots?.list,
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
      // A checked photo shows HD while the send options are high quality.
      highQuality: widget.panel.options.value.highQuality,
      viewerTitle: widget.viewerTitle,
      viewerSubtitleOf: GalleryView.viewerInfoOf,
      // A selected item a library change took away leaves the selection;
      // the ones after it move up a number.
      onRemoved: _$picker.remove,
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
      viewerBottomSlotHoldsKeyboard: true,
      onViewerClosed: _viewerClosed,
      // A long press on the viewer strip's item drags it in the order.
      onReorder: _$picker.move,
      // Picks from another album keep their marks in the viewer's strip.
      viewerAssetOf: _$picker.assetOf,
      // The sheet's scroll controller: a drag on the grid raises the sheet
      // to its top before the grid scrolls, and at the grid's top lowers or
      // dismisses it, in one gesture.
      controller: controller,
      lookup: _$lookup,
      gridBuilder: (context, grid) => GalleryFastScroll(
        controller: controller,
        lookup: _$lookup,
        policy: widget.panel.policy,
        child: grid,
      ),
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

/// The caption bar of the viewer's bottom slot, on a dock of its own.
///
/// The viewer's caption is its own field over the sheet caption's text: its
/// own focus and keyboard, so the field the viewer takes away when it goes
/// is its own, never the sheet's. Whenever the viewer's chrome goes (a
/// dismiss drag starting, a tap that hides the chrome) and whenever the
/// viewer closes (back, the close button, a dismiss, a send), the field
/// lets go: its panel closes, its focus goes, the keyboard goes down.
///
/// The sheet's caption is as the viewer found it: a panel that was up is
/// still up, and its caption has the focus again (its keyboard held back);
/// otherwise the focus is in the sheet's route on [sheetRest], never the
/// caption, so a keyboard that was down stays down and one that was up
/// (down as the viewer opened) does not come back.
class _ViewerCaption extends StatefulWidget {
  const _ViewerCaption({
    required this.controller,
    required this.item,
    required this.sheetRest,
    required this.chromeShown,
    required this.beforeSend,
    this.addMore,
    super.key,
  });

  final AttachSendController controller;

  /// The item shown, whose caption the field edits (the shared one, or its
  /// own, by the policy's rule); null for the shared caption.
  final AttachItem? item;
  final FocusNode sheetRest;

  /// Whether the viewer's chrome (this slot in it) is shown: false the
  /// moment it starts to go (a dismiss drag, a close, a tap that hides it).
  final ValueListenable<bool> chromeShown;
  final VoidCallback beforeSend;

  /// The caption's add-photo button, in the camera's viewer: back to the
  /// camera for another shot; null for none.
  final VoidCallback? addMore;

  @override
  State<_ViewerCaption> createState() => _ViewerCaptionState();
}

class _ViewerCaptionState extends State<_ViewerCaption> {
  // The field's own text, drawn as the sheet's is: it holds the caption of
  // the item shown and is loaded again as the page changes.
  late final ComposerTextController? _text = widget.controller.host
      .createCaptionText();
  late final ComposerController _caption = ComposerController(text: _text);

  AttachSelection get _selection => widget.controller.selection;
  var _loading = false;

  RichText get _shownCaption => switch (widget.item) {
    final item? => _selection.captionOf(item.id),
    null => _selection.caption,
  };

  // Loads the shown item's caption, unless the field already holds it
  // (an edit of ours coming back), so the caret stays where it is.
  void _load() {
    final caption = _shownCaption;
    if (caption == _caption.richText) return;
    _loading = true;
    try {
      _caption.restore(caption);
    } finally {
      _loading = false;
    }
  }

  void _edited() {
    if (_loading) return;
    final text = _caption.richText;
    if (text == _shownCaption) return;
    switch (widget.item) {
      case final item?:
        _selection.setCaptionOf(item, text);
      case null:
        _selection.caption = text;
    }
  }

  late final AttachCaptionDock? _dock = widget.controller.host
      .createCaptionDock(_caption);
  // Whether the sheet's caption panel was up as the viewer opened.
  late bool _sheetPanelWasUp;

  @override
  void initState() {
    super.initState();
    // The sheet's caption rests under the viewer: its panel's search
    // closes and the search's keyboard goes; its panel stays up.
    widget.controller.captionDock?.settle();
    _sheetPanelWasUp = widget.controller.captionDock?.panelUp ?? false;
    widget.chromeShown.addListener(_onChrome);
    _load();
    _caption.text.addListener(_edited);
    _selection.captionChanges.addListener(_load);
  }

  @override
  void didUpdateWidget(_ViewerCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chromeShown, widget.chromeShown)) {
      oldWidget.chromeShown.removeListener(_onChrome);
      widget.chromeShown.addListener(_onChrome);
    }
    // Another page: the field shows that item's caption.
    if (oldWidget.item?.id != widget.item?.id) _load();
  }

  // The chrome going (a dismiss drag starts, a tap hides it, a close): a
  // caption no one sees holds no keyboard.
  void _onChrome() {
    if (!widget.chromeShown.value) _letGo('the chrome goes');
  }

  void _letGo(String why) {
    final focused = _caption.focusNode.hasFocus;
    final panel = _dock?.panelUp ?? false;
    if (!focused && !panel) return;
    AttachLog.log(
      AttachLog.focus,
      'viewer caption lets go ($why): focus $focused, panel $panel',
    );
    _dock?.closePanel();
    if (focused) {
      _caption.focusNode.unfocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    }
  }

  @override
  void dispose() {
    _letGo('the viewer closes');
    widget.chromeShown.removeListener(_onChrome);
    final rest = widget.sheetRest;
    final sheetCaption = widget.controller.caption;
    final panelUp =
        _sheetPanelWasUp && (widget.controller.captionDock?.panelUp ?? false);
    // Once the viewer has gone, the focus is back in the sheet's route (a
    // route that asks for no focus of its own would leave it at the app's
    // root): on the caption under its panel, or on the sheet's rest.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (rest.context == null) return;
      AttachLog.log(
        AttachLog.focus,
        'viewer gone: focus back to the sheet '
        '(${panelUp ? 'the caption, its panel up' : 'its rest'})',
      );
      if (panelUp) {
        sheetCaption.requestFocus();
      } else {
        rest.requestFocus();
      }
    });
    _selection.captionChanges.removeListener(_load);
    _caption.text.removeListener(_edited);
    _dock?.dispose();
    _caption.dispose();
    _text?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    // Any close of the viewer lets go before it goes.
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _letGo('the viewer closes');
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AttachCaptionBar(
          controller: widget.controller,
          caption: _caption,
          dock: _dock,
          beforeSend: widget.beforeSend,
          addMore: widget.addMore,
        ),
        switch (_dock) {
          final dock? => dock.buildPlace(context),
          // With no dock the viewer does not lift the slot: the keyboard's
          // inset or the safe area, whichever is taller, under the bar.
          null => SizedBox(
            height: math.max(
              MediaQuery.viewInsetsOf(context).bottom,
              MediaQuery.viewPaddingOf(context).bottom,
            ),
          ),
        },
      ],
    ),
  );
}
