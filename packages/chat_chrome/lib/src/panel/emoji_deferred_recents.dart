import 'package:emoji_data/emoji_data.dart';

/// Snapshots [EmojiDataSource.recentGlyphs] for display while a panel is open.
///
/// Recents frequency updates must not reshuffle the visible row mid-session.
/// Call [commit] when opening the panel or leaving search; call [clear] after
/// the host clears history. Do **not** commit on every [EmojiDataSource]
/// notify while the panel stays open.
final class EmojiDeferredRecents {
  /// Creates an empty snapshot.
  EmojiDeferredRecents();

  List<String> _glyphs = const <String>[];

  /// Display glyphs (most-used first at last [commit]).
  List<String> get glyphs => _glyphs;

  /// Copies current source recents into the snapshot.
  void commit(EmojiDataSource source) {
    _glyphs = List<String>.from(source.recentGlyphs);
  }

  /// Clears the snapshot (e.g. after [EmojiDataSource.clearRecents]).
  void clear() {
    _glyphs = const <String>[];
  }
}
