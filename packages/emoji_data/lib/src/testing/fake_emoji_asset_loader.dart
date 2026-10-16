import 'package:emoji_data/src/loading/emoji_asset_loader.dart';

/// An [EmojiAssetLoader] over an in-memory map of asset texts.
///
/// Records every key it was asked for in [requested], so tests can assert
/// what was read and that nothing was read twice. A key missing from the map
/// fails like a missing asset in a bundle.
final class FakeEmojiAssetLoader {
  /// Creates a loader serving [assets], keyed by asset key.
  FakeEmojiAssetLoader(Map<String, String> assets)
    : _assets = Map<String, String>.of(assets);

  final Map<String, String> _assets;
  final List<String> _requested = <String>[];

  /// While set, every load fails with it, whatever the key.
  Exception? failure;

  /// The keys asked for so far, in request order, repeats included.
  List<String> get requested => List<String>.unmodifiable(_requested);

  /// Adds or replaces the text of [key].
  void put(String key, String text) => _assets[key] = text;

  /// The loader to hand to the code under test.
  Future<String> load(String key) async {
    _requested.add(key);
    if (failure case final error?) throw error;
    final text = _assets[key];
    if (text == null) throw StateError('No asset "$key".');
    return text;
  }
}
