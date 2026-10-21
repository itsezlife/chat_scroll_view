import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';

/// An in-memory [GlyphSupport] for tests: draws everything until a test says
/// otherwise.
///
/// Follows the whole seam contract. [learn] plays the part of a probe
/// finishing a step.
final class FakeGlyphSupport with ChangeNotifier implements GlyphSupport {
  final _missing = <ContentKey$Unicode>{};
  var _disposed = false;
  String? _artVersion;

  /// Establishes, in one step and one signal, that the [missing] keys are not
  /// drawn and that the emoji art is now [artVersion] (when given).
  ///
  /// A step that teaches nothing new signals nothing.
  void learn({Set<ContentKey$Unicode> missing = const {}, String? artVersion}) {
    if (_disposed) return;
    final newlyMissing = missing.difference(_missing);
    final versionChanged = artVersion != null && artVersion != _artVersion;
    if (newlyMissing.isEmpty && !versionChanged) return;
    _missing.addAll(newlyMissing);
    if (versionChanged) _artVersion = artVersion;
    notifyListeners();
  }

  @override
  Listenable get changes => this;

  @override
  String? get artVersion => _artVersion;

  @override
  bool supports(ContentKey$Unicode key) => !_missing.contains(key);

  // Idempotent: ChangeNotifier asserts on a second dispose, the seam does not.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
