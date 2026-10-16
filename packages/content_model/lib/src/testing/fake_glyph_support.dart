import 'package:content_model/content_model.dart';

/// An in-memory [GlyphSupport] for tests: draws everything until a test says
/// otherwise.
///
/// Follows the whole seam contract. [learn] plays the part of a probe
/// finishing a step.
final class FakeGlyphSupport implements GlyphSupport {
  final _missing = <ContentKey$Unicode>{};
  final _changes = ObservableNotifier();
  String? _artVersion;

  /// Establishes, in one step and one signal, that the [missing] keys are not
  /// drawn and that the emoji art is now [artVersion] (when given).
  ///
  /// A step that teaches nothing new signals nothing.
  void learn({Set<ContentKey$Unicode> missing = const {}, String? artVersion}) {
    if (_changes.isDisposed) return;
    final newlyMissing = missing.difference(_missing);
    final versionChanged = artVersion != null && artVersion != _artVersion;
    if (newlyMissing.isEmpty && !versionChanged) return;
    _missing.addAll(newlyMissing);
    if (versionChanged) _artVersion = artVersion;
    _changes.notify();
  }

  @override
  Observable get changes => _changes;

  @override
  String? get artVersion => _artVersion;

  @override
  bool supports(ContentKey$Unicode key) => !_missing.contains(key);

  @override
  void dispose() => _changes.dispose();
}
