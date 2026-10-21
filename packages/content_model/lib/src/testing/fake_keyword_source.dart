import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';

/// An in-memory [KeywordSource] for tests.
///
/// Follows the whole seam contract. [publish] plays the part of a server pack
/// arriving; [failure] makes reading an existing pack fail.
final class FakeKeywordSource with ChangeNotifier implements KeywordSource {
  /// Creates a source answering with [packs], keyed by their language.
  FakeKeywordSource([Iterable<KeywordPack> packs = const []]) {
    for (final pack in packs) {
      _packs[pack.language] = pack;
    }
  }

  final _packs = <String, KeywordPack>{};
  var _disposed = false;

  /// When non-null, [pack] fails with it whenever a pack exists for the
  /// language, as an unreadable pack would.
  Exception? failure;

  /// Adds [pack], or replaces the pack of its language, and signals once.
  void publish(KeywordPack pack) {
    if (_disposed) return;
    _packs[pack.language] = pack;
    notifyListeners();
  }

  @override
  Listenable get changes => this;

  @override
  Future<KeywordPack?> pack(String language) async {
    if (_disposed) return null;
    final found = _packs[language] ?? _packs[language.split('-').first];
    if (found != null && failure != null) throw failure!;
    return found;
  }

  // Idempotent: ChangeNotifier asserts on a second dispose, the seam does not.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
