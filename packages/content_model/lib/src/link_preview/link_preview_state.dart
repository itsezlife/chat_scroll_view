import 'package:content_model/src/link_preview/link_preview.dart';
import 'package:meta/meta.dart';

/// Where a link preview request stands: still looking, found a page, or
/// found none.
///
/// A request starts at [LinkPreviewState.pending] and moves once, to
/// [LinkPreviewState.loaded] or [LinkPreviewState.none]; the last two are
/// terminal. A failed lookup is [LinkPreviewState.none] too: a caller shows
/// no card either way, and the resolver reports why through its own
/// diagnostics.
@immutable
sealed class LinkPreviewState {
  /// A page was found.
  const factory LinkPreviewState.loaded(LinkPreview page) =
      LinkPreviewState$Loaded;

  const LinkPreviewState._();

  /// The lookup is in flight.
  static const LinkPreviewState pending = LinkPreviewState$Pending();

  /// No page: none of the candidates has one, or the lookup failed.
  static const LinkPreviewState none = LinkPreviewState$None();

  /// Whether the state is [loaded] or [none]: the request moves no more.
  bool get isTerminal;
}

/// The [LinkPreviewState.pending] state.
final class LinkPreviewState$Pending extends LinkPreviewState {
  /// Creates the pending state.
  const LinkPreviewState$Pending() : super._();

  @override
  bool get isTerminal => false;

  @override
  bool operator ==(Object other) => other is LinkPreviewState$Pending;

  @override
  int get hashCode => (LinkPreviewState$Pending).hashCode;

  @override
  String toString() => 'pending';
}

/// The [LinkPreviewState.loaded] state.
final class LinkPreviewState$Loaded extends LinkPreviewState {
  /// Creates the loaded state for [page].
  const LinkPreviewState$Loaded(this.page) : super._();

  /// The page found.
  final LinkPreview page;

  @override
  bool get isTerminal => true;

  @override
  bool operator ==(Object other) =>
      other is LinkPreviewState$Loaded && other.page == page;

  @override
  int get hashCode => Object.hash(LinkPreviewState$Loaded, page);

  @override
  String toString() => 'loaded($page)';
}

/// The [LinkPreviewState.none] state.
final class LinkPreviewState$None extends LinkPreviewState {
  /// Creates the none state.
  const LinkPreviewState$None() : super._();

  @override
  bool get isTerminal => true;

  @override
  bool operator ==(Object other) => other is LinkPreviewState$None;

  @override
  int get hashCode => (LinkPreviewState$None).hashCode;

  @override
  String toString() => 'none';
}
