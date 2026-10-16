import 'package:content_model/content_model.dart';

/// An in-memory [KeywordSource] for tests.
///
/// Follows the whole seam contract. [publish] plays the part of a server pack
/// arriving; [failure] makes reading an existing pack fail.
final class FakeKeywordSource implements KeywordSource {
  /// Creates a source answering with [packs], keyed by their language.
  FakeKeywordSource([Iterable<KeywordPack> packs = const []]) {
    for (final pack in packs) {
      _packs[pack.language] = pack;
    }
  }

  final _packs = <String, KeywordPack>{};
  final _changes = ObservableNotifier();

  /// When non-null, [pack] fails with it whenever a pack exists for the
  /// language, as an unreadable pack would.
  Exception? failure;

  /// Adds [pack], or replaces the pack of its language, and signals once.
  void publish(KeywordPack pack) {
    if (_changes.isDisposed) return;
    _packs[pack.language] = pack;
    _changes.notify();
  }

  @override
  Observable get changes => _changes;

  @override
  Future<KeywordPack?> pack(String language) async {
    if (_changes.isDisposed) return null;
    final found = _packs[language] ?? _packs[language.split('-').first];
    if (found != null && failure != null) throw failure!;
    return found;
  }

  @override
  void dispose() => _changes.dispose();
}
