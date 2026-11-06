import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads content files from an asset bundle, the file of a key being whatever
/// [pathOf] says.
///
/// A bundle read cannot be stopped, so a cancelled fetch still completes with
/// its bytes, which the pipeline drops. A key [pathOf] has no file for, or a
/// file the bundle lacks, is missing content: a permanent failure. Bundled
/// packs have no thumbnails, so none is served.
final class BundleFetcher implements ContentFetcher {
  /// Creates a fetcher of [bundle]'s files; [pathOf] returns null for a key
  /// that is not bundled.
  BundleFetcher(this._bundle, {required String? Function(ContentKey) pathOf})
    : _pathOf = pathOf;

  final AssetBundle _bundle;
  final String? Function(ContentKey) _pathOf;

  @override
  Future<FetchedContent> fetch(FetchRequest request) async {
    final path = _pathOf(request.descriptor.key);
    if (path == null || request.part == FetchPart.thumbnail) {
      throw FetchFailure.permanent(
        'not in the bundled packs: ${request.descriptor.key} '
        '(${request.part.name})',
      );
    }
    final ByteData data;
    try {
      data = await _bundle.load(path);
      // A bundle reports a file it lacks as a FlutterError and offers no way
      // to ask first.
      // ignore: avoid_catching_errors
    } on FlutterError catch (error) {
      // A bundle does not gain files at run time, so retrying will not help.
      // Anything else is a bug, and stays one.
      throw FetchFailure.permanent('missing $path', error);
    }
    return FetchedContent.bytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}
