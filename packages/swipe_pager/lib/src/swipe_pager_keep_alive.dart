import 'package:flutter/foundation.dart';

/// Which pages a swipe pager keeps built once they leave the screen.
///
/// A kept page keeps its state (scroll positions, controllers, loaded
/// content) and is offstage, out of focus and semantics, under
/// `TickerMode(enabled: false)`; a page that is not kept is disposed and
/// built anew when it shows again. The pages on screen are always built.
///
/// Recency counts the pages the pager settled on, most recent first: the
/// page it rests on is the most recent.
sealed class SwipePagerKeepAlive {
  const SwipePagerKeepAlive._();

  /// Every page once built stays built for the life of the pager.
  const factory SwipePagerKeepAlive.all() = SwipePagerKeepAlive$All;

  /// Only the pages on screen are built.
  const factory SwipePagerKeepAlive.none() = SwipePagerKeepAlive$None;

  /// The [pages] most recently settled on stay built, the page the pager
  /// rests on among them; [pages] is at least 1.
  const factory SwipePagerKeepAlive.recent(int pages) =
      SwipePagerKeepAlive$Recent;

  /// Whether the page that is [rank]th in recency (0 is the page the pager
  /// rests on) stays built.
  bool keeps(int rank);
}

/// [SwipePagerKeepAlive.all].
@immutable
final class SwipePagerKeepAlive$All extends SwipePagerKeepAlive {
  /// Every page stays built.
  const SwipePagerKeepAlive$All() : super._();

  @override
  bool keeps(int rank) => true;

  @override
  bool operator ==(Object other) => other is SwipePagerKeepAlive$All;

  @override
  int get hashCode => (SwipePagerKeepAlive$All).hashCode;
}

/// [SwipePagerKeepAlive.none].
@immutable
final class SwipePagerKeepAlive$None extends SwipePagerKeepAlive {
  /// Only the pages on screen are built.
  const SwipePagerKeepAlive$None() : super._();

  @override
  bool keeps(int rank) => false;

  @override
  bool operator ==(Object other) => other is SwipePagerKeepAlive$None;

  @override
  int get hashCode => (SwipePagerKeepAlive$None).hashCode;
}

/// [SwipePagerKeepAlive.recent].
@immutable
final class SwipePagerKeepAlive$Recent extends SwipePagerKeepAlive {
  /// The [pages] most recently settled on stay built.
  const SwipePagerKeepAlive$Recent(this.pages)
    : assert(pages >= 1, 'a pager keeps at least the page it rests on'),
      super._();

  /// How many pages stay built.
  final int pages;

  @override
  bool keeps(int rank) => rank < pages;

  @override
  bool operator ==(Object other) =>
      other is SwipePagerKeepAlive$Recent && other.pages == pages;

  @override
  int get hashCode => pages.hashCode;
}
