import 'package:content_model/content_model.dart';

/// A [KeywordSource] that answers from a host's source first and from a
/// baseline underneath: the bundled packs are the offline floor, whatever the
/// host supplies sits on top.
///
/// For a language both have, the pack is the baseline's with the host's
/// records laid over it: a key the host lists takes the host's keywords (a
/// server pack is the newer word), a key only the baseline lists keeps its
/// own. The merged pack carries the host pack's language and version. A
/// language only one of them has is answered by that pack unchanged.
///
/// The merge is computed once per pair of packs and shared until either input
/// answers with another pack. [changes] signals whenever either input does.
///
/// The inputs belong to the caller: [dispose] stops listening to them and
/// does not dispose them.
final class LayeredKeywordSource implements KeywordSource {
  /// Layers [overlay] over [base].
  LayeredKeywordSource({required this.base, required this.overlay}) {
    base.changes.addListener(_changes.notify);
    overlay.changes.addListener(_changes.notify);
  }

  /// The baseline, answering where the overlay has nothing.
  final KeywordSource base;

  /// The host's source, answering first.
  final KeywordSource overlay;

  final ObservableNotifier _changes = ObservableNotifier();
  final Map<String, _Merge> _merged = {};

  @override
  Observable get changes => _changes;

  @override
  Future<KeywordPack?> pack(String language) async {
    if (_changes.isDisposed) return null;
    final lower = await base.pack(language);
    final upper = await overlay.pack(language);
    if (_changes.isDisposed) return null;
    if (lower == null || upper == null) return upper ?? lower;
    final known = _merged[language];
    if (known != null &&
        identical(known.lower, lower) &&
        identical(known.upper, upper)) {
      return known.pack;
    }
    final pack = KeywordPack(
      language: upper.language,
      version: upper.version,
      keywords: {...lower.keywords, ...upper.keywords},
    );
    _merged[language] = _Merge(lower, upper, pack);
    return pack;
  }

  @override
  void dispose() {
    base.changes.removeListener(_changes.notify);
    overlay.changes.removeListener(_changes.notify);
    _changes.dispose();
    _merged.clear();
  }
}

final class _Merge {
  const _Merge(this.lower, this.upper, this.pack);

  final KeywordPack lower;
  final KeywordPack upper;
  final KeywordPack pack;
}
