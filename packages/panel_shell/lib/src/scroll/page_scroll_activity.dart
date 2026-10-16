import 'package:meta/meta.dart';

/// What the scroll of the active page is doing, as a page reports it to the
/// shell: the typed input behind bottom-bar hide and show.
///
/// The shell derives visibility from these values alone. It reads no clock
/// and no scroll position: a page that knows a scroll was programmatic says
/// so with [PageScrollJump] instead of leaving the shell to guess from timing.
///
/// Deltas are in logical pixels and positive when the content moves toward its
/// end (the user is reading on), negative toward its start.
@immutable
sealed class PageScrollActivity {
  const PageScrollActivity();
}

/// The user's finger is moving the content by [delta] pixels.
final class PageScrollDrag extends PageScrollActivity {
  /// A drag step of [delta] pixels.
  const PageScrollDrag(this.delta);

  /// Pixels moved by this step; see [PageScrollActivity] for the sign.
  final double delta;

  @override
  bool operator ==(Object other) =>
      other is PageScrollDrag && other.delta == delta;

  @override
  int get hashCode => Object.hash(PageScrollDrag, delta);

  @override
  String toString() => 'PageScrollDrag($delta)';
}

/// The content is coasting after release, moving by [delta] pixels this step.
final class PageScrollFling extends PageScrollActivity {
  /// A fling step of [delta] pixels.
  const PageScrollFling(this.delta);

  /// Pixels moved by this step; see [PageScrollActivity] for the sign.
  final double delta;

  @override
  bool operator ==(Object other) =>
      other is PageScrollFling && other.delta == delta;

  @override
  int get hashCode => Object.hash(PageScrollFling, delta);

  @override
  String toString() => 'PageScrollFling($delta)';
}

/// The page scrolls by itself (a jump to a section, a scroll to top): the
/// bottom bar is shown and any distance accumulated so far is forgotten.
///
/// Reported once when the programmatic scroll starts; the page follows with
/// [PageScrollIdle] when it ends. Deltas of the scroll are not reported.
final class PageScrollJump extends PageScrollActivity {
  /// A programmatic scroll started.
  const PageScrollJump();

  @override
  bool operator ==(Object other) => other is PageScrollJump;

  @override
  int get hashCode => (PageScrollJump).hashCode;

  @override
  String toString() => 'PageScrollJump()';
}

/// The content stopped moving.
final class PageScrollIdle extends PageScrollActivity {
  /// The content is at rest; [atEdge] tells whether it rests at either end.
  const PageScrollIdle({this.atEdge = false});

  /// Whether the content rests at its start or its end, where the bottom bar
  /// is always shown because there is nothing left to read past it.
  final bool atEdge;

  @override
  bool operator ==(Object other) =>
      other is PageScrollIdle && other.atEdge == atEdge;

  @override
  int get hashCode => Object.hash(PageScrollIdle, atEdge);

  @override
  String toString() => 'PageScrollIdle(atEdge: $atEdge)';
}
