import 'package:content_model/src/link_preview/link_preview.dart';
import 'package:content_model/src/link_preview/link_preview_state.dart';
import 'package:listen/listen.dart';

/// Turns the URLs found in a text into the page its link preview shows.
///
/// The host implements it, because only the host knows where pages come
/// from: a messaging backend that has already fetched them, or a client-side
/// fetch the host has decided to allow (a fetch of a third-party page reveals
/// the user's address to that site and follows its redirects, so no package
/// does one on its own).
///
/// ## Candidates
///
/// [resolve] takes every candidate URL, in text order, so both backend
/// shapes fit: one that picks among all of them, and one that tries them in
/// order and stops at the first page. An empty list resolves to
/// [LinkPreviewState.none].
///
/// ## The request
///
/// The answer is a [LinkPreviewRequest], not a future, so a caller can drop
/// a lookup the user has typed past. It starts at
/// [LinkPreviewState.pending] and moves once, to [LinkPreviewState.loaded]
/// or [LinkPreviewState.none], notifying its listeners at that one move. A
/// lookup that fails ends at [LinkPreviewState.none]; [resolve] itself does
/// not throw, though a caller guards it anyway, since it is host code. Every
/// call gives a new request; resolving the same candidates again is always
/// allowed.
///
/// [LinkPreviewCompleter] gives an implementation a request that keeps these
/// rules.
abstract interface class LinkPreviewResolver {
  /// Looks up the page for [candidates].
  LinkPreviewRequest resolve(List<Uri> candidates);
}

/// One lookup of a [LinkPreviewResolver]: its state as a listenable value,
/// and a way to drop it.
///
/// [value] starts at [LinkPreviewState.pending] and changes at most once, to
/// a terminal state, with one notification.
abstract interface class LinkPreviewRequest
    implements ValueListenable<LinkPreviewState> {
  /// Drops the lookup: the request notifies no more, and the resolver may
  /// stop its backend work.
  ///
  /// [value] stays where it was. Safe to call more than once, and a no-op
  /// once the request has reached a terminal state.
  void cancel();
}

/// The producer side of a [LinkPreviewRequest], for resolver
/// implementations: it keeps the request's rules (one move, nothing after a
/// terminal state or a cancel) so each resolver does not write them again.
///
/// A resolver returns [request] from `resolve` and calls [complete] when its
/// backend answers. A [complete] after the request was cancelled or already
/// completed is ignored, so a late backend answer needs no check.
final class LinkPreviewCompleter {
  /// A completer whose request is pending.
  ///
  /// [onCancel] runs once, when the pending request is cancelled: the
  /// resolver's hook to abort its backend work.
  LinkPreviewCompleter({void Function()? onCancel})
    : _request = _CompletableLinkPreviewRequest(onCancel);

  final _CompletableLinkPreviewRequest _request;

  /// The request this completer ends.
  LinkPreviewRequest get request => _request;

  /// Whether the request moves no more: it reached a terminal state or was
  /// cancelled.
  bool get isSettled => _request.isSettled;

  /// Whether the request was cancelled while pending.
  bool get isCancelled => _request.isCancelled;

  /// Ends the request at [LinkPreviewState.loaded] with [page], or at
  /// [LinkPreviewState.none] when [page] is null.
  ///
  /// Ignored when the request has already settled.
  void complete(LinkPreview? page) => _request.settle(switch (page) {
    null => LinkPreviewState.none,
    final page => LinkPreviewState.loaded(page),
  });
}

final class _CompletableLinkPreviewRequest
    with ChangeNotifier
    implements LinkPreviewRequest {
  _CompletableLinkPreviewRequest(this._onCancel);

  // Cleared at cancel so it runs at most once and the resolver's work it
  // captures can be collected.
  void Function()? _onCancel;

  LinkPreviewState _value = LinkPreviewState.pending;
  bool _cancelled = false;

  @override
  LinkPreviewState get value => _value;

  bool get isCancelled => _cancelled;

  bool get isSettled => _cancelled || _value.isTerminal;

  void settle(LinkPreviewState state) {
    if (isSettled) return;
    _value = state;
    notifyListeners();
  }

  @override
  void cancel() {
    if (isSettled) return;
    _cancelled = true;
    final onCancel = _onCancel;
    _onCancel = null;
    onCancel?.call();
  }
}
