import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/panel/attach_interaction.dart';
import 'package:flutter/foundation.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_ui/mpx_ui.dart';

/// The library grid's picker selection over the open's attach selection:
/// library picks, files and captures share one order, and the grid's gate
/// is the attach limits' and the policy's cap.
///
/// The grid names assets by their library key; the selection needs the
/// asset's kind and facts, which [AttachPickerSelection.library] records as
/// pages pass through it (give the grid that library, not the host's).
final class AttachPickerSelection implements PickerSelection {
  /// A picker selection over [selection], reading assets from [source].
  AttachPickerSelection({
    required this.selection,
    required MediaLibrary source,
    this.onRefused,
  }) : _recording = _RecordingLibrary(source) {
    _recording._selection = selection;
  }

  /// The open's attach selection.
  final AttachSelection selection;

  /// Called with each refusal, as an attach interaction.
  final ValueChanged<AttachInteraction>? onRefused;

  final _RecordingLibrary _recording;

  /// The library to give the grid: the host's, recording each asset it
  /// pages.
  MediaLibrary get library => _recording;

  /// The album [library] answers with the selected library items, in their
  /// order: what the viewer pages when opened from the selected-items
  /// preview.
  static const LibraryAlbumId selectedAlbum = LibraryAlbumId('attach:selected');

  /// The selected library assets, in the selection's order.
  List<LibraryAsset> get selectedAssets => _recording.selectedAssets(selection);

  /// The [selectedAlbum] as it is now.
  LibraryAlbum get selectedAlbumNow => LibraryAlbum(
    id: selectedAlbum,
    kind: LibraryAlbumKind.system,
    title: '',
    count: selectedAssets.length,
  );

  /// Moves the library item of [key] to the place [to] among the selected
  /// library items (the preview's order); files and captures keep theirs.
  void move(MediaKey key, int to) {
    final target = LibraryKeys.read(key);
    if (target == null) return;
    final items = selection.items;
    final places = [
      for (var i = 0; i < items.length; i++)
        if (items[i].source is AttachSource$Library) i,
    ];
    final from = items.indexWhere((item) => item.id == idOf(target.asset));
    if (from < 0 || to < 0 || to >= places.length) return;
    selection.reorder(from, places[to]);
  }

  /// The attach item of a library asset.
  static AttachItem itemOf(LibraryAsset asset) => AttachItem(
    id: idOf(asset.id),
    source: AttachSource.library(asset.id.value),
    kind: switch (asset.kind) {
      LibraryAssetKind.photo when asset.has(LibraryAssetSubtype.animated) =>
        AttachKind.animation,
      LibraryAssetKind.photo => AttachKind.photo,
      LibraryAssetKind.video => AttachKind.video,
    },
    facts: AttachFacts(
      dimensions: switch (asset.dimensions) {
        final d? => AttachDimensions(d.width, d.height),
        null => null,
      },
      duration: asset.duration,
      mimeType: asset.mimeType,
      modified: asset.modified,
    ),
  );

  /// The attach item id of library asset [id].
  static AttachItemId idOf(LibraryAssetId id) =>
      AttachItemId('library:${id.value}');

  AttachItem? _itemOf(MediaKey key) {
    final target = LibraryKeys.read(key);
    if (target == null) return null;
    final asset = _recording.assets[target.asset];
    if (asset != null) return itemOf(asset);
    // Not paged through here (a key the grid kept from elsewhere): the
    // selection may still hold it.
    final id = idOf(target.asset);
    for (final item in selection.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  List<MediaKey> get keys => [
    for (final item in selection.items)
      if (item.source case AttachSource$Library(:final assetId))
        LibraryKeys.keyOf(LibraryAssetId(assetId)),
  ];

  @override
  int? orderOf(MediaKey key) => switch (LibraryKeys.read(key)) {
    final target? => selection.orderOf(idOf(target.asset)),
    null => null,
  };

  @override
  PickerRefusal? refusalOf(MediaKey key) => switch (_itemOf(key)) {
    final item? => _pickerReason(selection.refusalOf(item)),
    null => null,
  };

  @override
  PickerToggle toggle(MediaKey key) {
    final item = _itemOf(key);
    if (item == null) return const PickerToggle$Refused(PickerRefusal.other);
    return _toPicker(selection.toggle(item), item);
  }

  @override
  List<(MediaKey, PickerRefusal)> toggleRange(List<MediaKey> keys, {bool? to}) {
    final refused = <(MediaKey, PickerRefusal)>[];
    final items = [for (final key in keys) (key, _itemOf(key))];
    final first = items.isEmpty ? null : items.first.$2;
    final select = to ?? !(first != null && selection.contains(first.id));
    for (final (key, item) in items) {
      if (item == null) {
        refused.add((key, PickerRefusal.other));
        continue;
      }
      if (selection.contains(item.id) == select) continue;
      final result = selection.toggle(item);
      if (result case AttachToggle$Refused(:final reason)) {
        refused.add((key, _pickerReason(reason)!));
        onRefused?.call(AttachInteraction.refused(reason));
      }
    }
    return refused;
  }

  PickerToggle _toPicker(AttachToggle toggle, AttachItem item) =>
      switch (toggle) {
        AttachToggle$Selected() => PickerToggle$Selected(
          selection.orderOf(item.id) ?? 0,
        ),
        AttachToggle$Deselected() => const PickerToggle$Deselected(),
        AttachToggle$Refused(:final reason) => _refuse(reason),
      };

  PickerToggle _refuse(AttachRefusal reason) {
    onRefused?.call(AttachInteraction.refused(reason));
    return PickerToggle$Refused(_pickerReason(reason)!);
  }

  static PickerRefusal? _pickerReason(AttachRefusal? reason) =>
      switch (reason) {
        AttachRefusal.capReached => PickerRefusal.cap,
        AttachRefusal.kindNotAllowed => PickerRefusal.kind,
        AttachRefusal.fileTooLarge ||
        AttachRefusal.emptyFile => PickerRefusal.other,
        null => null,
      };

  @override
  void addListener(VoidCallback listener) =>
      selection.changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      selection.changes.removeListener(listener);
}

/// The host's library, recording every asset it pages to the grid.
final class _RecordingLibrary implements MediaLibrary {
  _RecordingLibrary(this._source);

  final MediaLibrary _source;
  final Map<LibraryAssetId, LibraryAsset> assets = {};

  List<LibraryAsset> selectedAssets(AttachSelection selection) => [
    for (final item in selection.items)
      if (item.source case AttachSource$Library(:final assetId))
        ?assets[LibraryAssetId(assetId)],
  ];

  AttachSelection? _selection;

  @override
  ValueListenable<LibraryAccess> get access => _source.access;

  @override
  Future<LibraryAccess> requestAccess() => _source.requestAccess();

  @override
  Future<bool> manageSelected() => _source.manageSelected();

  @override
  Future<void> openSettings() => _source.openSettings();

  @override
  Future<List<LibraryAlbum>> albums() => _source.albums();

  @override
  Future<LibraryPage> page(
    LibraryAlbumId album, {
    required int offset,
    required int limit,
  }) async {
    if (album == AttachPickerSelection.selectedAlbum) {
      final selected = switch (_selection) {
        final selection? => selectedAssets(selection),
        null => const <LibraryAsset>[],
      };
      return LibraryPage(
        album: album,
        offset: offset,
        assets: selected.skip(offset).take(limit).toList(),
        total: selected.length,
      );
    }
    final page = await _source.page(album, offset: offset, limit: limit);
    for (final asset in page.assets) {
      assets[asset.id] = asset;
    }
    return page;
  }

  @override
  Stream<LibraryChange> get changes => _source.changes;

  @override
  Future<Uint8List> thumbnail(
    LibraryAssetId asset, {
    required int pixels,
    CancellationToken? cancellation,
  }) => _source.thumbnail(asset, pixels: pixels, cancellation: cancellation);

  @override
  Future<LibraryFileLease> original(
    LibraryAssetId asset, {
    FetchProgress? onProgress,
    CancellationToken? cancellation,
  }) => _source.original(
    asset,
    onProgress: onProgress,
    cancellation: cancellation,
  );

  @override
  bool isCloudHeld(LibraryAssetId asset) => _source.isCloudHeld(asset);

  @override
  Future<Uri?> playable(LibraryAssetId asset) => _source.playable(asset);

  /// The host owns the library; the grid does not end it.
  @override
  Future<void> dispose() async {}
}
