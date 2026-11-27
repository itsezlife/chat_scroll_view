import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/gallery/gallery_captures.dart';
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
    this.onItemRefused,
    this.captures,
  }) : _recording = _RecordingLibrary(source) {
    _recording
      .._selection = selection
      .._captures = captures;
  }

  /// The open's attach selection.
  final AttachSelection selection;

  /// Called with each refusal, as an attach interaction.
  final ValueChanged<AttachInteraction>? onRefused;

  /// Called with each refusal and the item refused, in place of
  /// [onRefused]: the panel's `refused`, which sends a kind the chat denies
  /// to the host's `onDenied`.
  final void Function(AttachItem item, AttachRefusal reason)? onItemRefused;

  /// The camera's captures, whose keys the grid also checks; null for
  /// none.
  final GalleryCaptures? captures;

  final _RecordingLibrary _recording;

  /// The library to give the grid: the host's, recording each asset it
  /// pages.
  MediaLibrary get library => _recording;

  /// The album [library] answers with the selected library items and
  /// captures, in their order: what the viewer pages when opened from the
  /// selected-items preview.
  static const LibraryAlbumId selectedAlbum = LibraryAlbumId('attach:selected');

  /// The selected library assets and captures (as their assets), in the
  /// selection's order.
  List<LibraryAsset> get selectedAssets => _recording.selectedAssets(selection);

  /// Where [key] stands in [selectedAlbum], or null when it is not there.
  int? selectedIndexOf(MediaKey key) {
    final index = selectedAssets.indexWhere(
      (asset) => PickerCaptureKeys.keyOf(asset) == key,
    );
    return index < 0 ? null : index;
  }

  /// The [selectedAlbum] as it is now.
  LibraryAlbum get selectedAlbumNow => LibraryAlbum(
    id: selectedAlbum,
    kind: LibraryAlbumKind.system,
    title: '',
    count: selectedAssets.length,
  );

  /// Moves the item of [key] (a library item or a capture) to the place
  /// [to] among the picks the picker shows ([keys]: the preview's and the
  /// viewer strip's order); files keep their places.
  void move(MediaKey key, int to) {
    final id = _idOfKey(key);
    if (id == null) return;
    final items = selection.items;
    final places = [
      for (var i = 0; i < items.length; i++)
        if (_shown(items[i])) i,
    ];
    final from = items.indexWhere((item) => item.id == id);
    if (from < 0 || to < 0 || to >= places.length) return;
    selection.reorder(from, places[to]);
  }

  // Whether the picker shows [item] among its picks ([keys]).
  static bool _shown(AttachItem item) => switch (item.source) {
    AttachSource$Library() => true,
    AttachSource$Captured(:final localKey) =>
      MediaKey.tryParse(localKey) != null,
    _ => false,
  };

  // The attach item id the picker's [key] stands for.
  AttachItemId? _idOfKey(MediaKey key) => switch (key) {
    final MediaKey$Local local => GalleryCaptures.idOf(local),
    _ => switch (LibraryKeys.read(key)) {
      final target? => idOf(target.asset),
      null => null,
    },
  };

  /// Drops the library items of [keys] from the selection (a library change
  /// took them away: deleted on the device, or no longer allowed); the
  /// items after them move up a number, files and captures included.
  void remove(List<MediaKey> keys) {
    for (final key in keys) {
      final target = LibraryKeys.read(key);
      if (target == null) continue;
      final id = idOf(target.asset);
      for (final item in selection.items) {
        if (item.id == id) {
          selection.toggle(item);
          break;
        }
      }
      _recording.assets.remove(target.asset);
    }
  }

  /// The asset of [key]: a library item as the grid paged it, or a
  /// capture's asset (which carries its thumbnail, a recording's first
  /// frame); null otherwise.
  LibraryAsset? assetOf(MediaKey key) => switch (key) {
    final MediaKey$Local local => captures?.captureOf(local)?.asset,
    _ => switch (LibraryKeys.read(key)) {
      final target? => _recording.assets[target.asset],
      null => null,
    },
  };

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
    if (key case final MediaKey$Local local) {
      if (captures?.captureOf(local) case final capture?) {
        return GalleryCaptures.itemOf(capture);
      }
      final id = GalleryCaptures.idOf(local);
      for (final item in selection.items) {
        if (item.id == id) return item;
      }
      return null;
    }
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
      ?switch (item.source) {
        AttachSource$Library(:final assetId) => LibraryKeys.keyOf(
          LibraryAssetId(assetId),
        ),
        AttachSource$Captured(:final localKey) => MediaKey.tryParse(localKey),
        _ => null,
      },
  ];

  @override
  int? orderOf(MediaKey key) => switch (key) {
    final MediaKey$Local local => selection.orderOf(
      GalleryCaptures.idOf(local),
    ),
    _ => switch (LibraryKeys.read(key)) {
      final target? => selection.orderOf(idOf(target.asset)),
      null => null,
    },
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
        _report(item, reason);
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
        AttachToggle$Refused(:final reason) => _refuse(item, reason),
      };

  PickerToggle _refuse(AttachItem item, AttachRefusal reason) {
    _report(item, reason);
    return PickerToggle$Refused(_pickerReason(reason)!);
  }

  void _report(AttachItem item, AttachRefusal reason) {
    if (onItemRefused case final report?) return report(item, reason);
    onRefused?.call(AttachInteraction.refused(reason));
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
      ?switch (item.source) {
        AttachSource$Library(:final assetId) => assets[LibraryAssetId(assetId)],
        AttachSource$Captured(:final localKey) => switch (MediaKey.tryParse(
          localKey,
        )) {
          final MediaKey$Local local => _captures?.captureOf(local)?.asset,
          _ => null,
        },
        _ => null,
      },
  ];

  AttachSelection? _selection;
  GalleryCaptures? _captures;

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
  Future<Set<LibraryAssetId>> missing(Iterable<LibraryAssetId> assets) =>
      _source.missing(assets);

  @override
  Future<Uri?> playable(LibraryAssetId asset) => _source.playable(asset);

  /// The host owns the library; the grid does not end it.
  @override
  Future<void> dispose() async {}
}
