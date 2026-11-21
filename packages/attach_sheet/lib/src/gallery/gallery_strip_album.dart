import 'package:flutter/foundation.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_ui/mpx_ui.dart';

/// The album the Gallery's grid shows, as the camera page's strip lists it
/// after the shots: the same pages the grid reads, so the strip offers every
/// item the grid does, by the same library keys the selection holds.
final class GalleryStripAlbum extends ChangeNotifier
    implements CaptureStripGallery {
  /// The strip's view of [pages].
  GalleryStripAlbum(this.pages) {
    pages.addListener(notifyListeners);
  }

  /// The grid's pages of the album.
  final LibraryPages pages;

  @override
  int get count => pages.total;

  @override
  CaptureStripItem? itemAt(int index, {required int thumbnailPixels}) {
    final asset = pages.assetAt(index);
    if (asset == null) return null;
    return CaptureStripItem(
      key: LibraryKeys.keyOf(asset.id),
      thumbnail: MediaDescriptor(
        key: LibraryKeys.thumbnailKeyFor(asset.id, thumbnailPixels),
        kind: MediaKind.still,
      ),
      duration: asset.kind == LibraryAssetKind.video ? asset.duration : null,
    );
  }

  @override
  void dispose() {
    pages.removeListener(notifyListeners);
    super.dispose();
  }
}
