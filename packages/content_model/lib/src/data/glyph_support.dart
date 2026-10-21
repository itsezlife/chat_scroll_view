import 'package:content_model/src/identity/content_key.dart';
import 'package:listen/listen.dart';

/// Answers which unicode keys the device can draw, so pages can hide emoji it
/// would show as blanks or boxes.
///
/// The answer is synchronous and optimistic: [supports] is `true` until
/// support has been established to be missing. A source that learns slowly,
/// by probing glyphs a few per frame, therefore never hides anything it has
/// not checked, and one without any means of checking leaves everything
/// visible. When it learns something it publishes once on [changes], however
/// many keys the step covered.
///
/// ## Art version
///
/// [artVersion] names the system emoji art the answers were established
/// against: it changes when the device's emoji art changes, for example after
/// a system update. Whoever caches anything derived from the device's emoji
/// art (including answers of this seam) keys it on this value. It is null
/// until the source knows it. A change of [artVersion] is signalled on
/// [changes] together with any answers it invalidated, in one publication.
///
/// After [dispose] [changes] is silent and the last answers stay readable.
abstract interface class GlyphSupport {
  /// Signals when some [supports] answer or [artVersion] changed.
  Listenable get changes;

  /// The identity of the device's emoji art, or null while unknown.
  String? get artVersion;

  /// Whether the device draws [key]. `true` unless known to be missing.
  bool supports(ContentKey$Unicode key);

  /// Releases the source and its listeners.
  void dispose();
}
