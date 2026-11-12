/// Strings of a bulletin's own chrome: its Undo action and the spoken
/// dismiss action.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. A bulletin's message and title are the caller's, not these.
final class BulletinStrings {
  /// Bulletin strings with every member given.
  const BulletinStrings({
    required this.undoAction,
    required this.dismissAction,
  });

  /// The label of an Undo bulletin's action.
  final String undoAction;

  /// The spoken name of the action that dismisses a bulletin.
  final String dismissAction;
}
