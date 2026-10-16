import 'dart:io';
import 'dart:isolate';

import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';

/// The text of a shipped asset of `emoji_catalog_pack`, by its asset key, read
/// from the package's directory: the loader a Flutter host would back with its
/// bundle, here backed with the files.
Future<String> readShippedAsset(String key) async {
  const prefix = 'packages/emoji_catalog_pack/';
  if (!key.startsWith(prefix)) throw StateError('Not a pack asset: $key');
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:emoji_catalog_pack/emoji_catalog_pack.dart'),
  );
  final path = library!.resolve('../${key.substring(prefix.length)}');
  return File.fromUri(path).readAsString();
}

/// Every asset key a host would need for [locales], for a fake loader.
Iterable<String> shippedKeys(Iterable<String> locales) => [
  EmojiCatalogPackAssets.structure,
  for (final locale in locales) EmojiCatalogPackAssets.keywordPack(locale),
];
