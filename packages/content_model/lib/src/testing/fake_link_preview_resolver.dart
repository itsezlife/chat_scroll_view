import 'package:content_model/content_model.dart';
import 'package:content_model/src/value_equality.dart';

/// An in-memory [LinkPreviewResolver] for tests, answering candidate lists
/// it was scripted with and completing on demand.
///
/// Follows the whole seam contract. Requests stay
/// [LinkPreviewState.pending] until [completeAll], so a test can type past a
/// lookup in flight. A candidate list that was never [answer]ed ends at
/// [LinkPreviewState.none]. [calls] records each [resolve] call and
/// [cancels] each request cancelled while pending; [failure] makes [resolve]
/// throw, as a broken host resolver would.
final class FakeLinkPreviewResolver implements LinkPreviewResolver {
  /// A resolver that knows no page yet.
  FakeLinkPreviewResolver();

  final _answers = <(List<Uri>, LinkPreview?)>[];
  final _calls = <List<Uri>>[];
  final _cancels = <List<Uri>>[];
  final _inFlight = <(List<Uri>, LinkPreviewCompleter)>[];

  /// When non-null, [resolve] throws it.
  Exception? failure;

  /// Scripts the answer for exactly [candidates], in this order: [page], or
  /// no page when [page] is null. A later answer for the same list replaces
  /// the earlier one.
  void answer(List<Uri> candidates, LinkPreview? page) {
    _answers
      ..removeWhere((entry) => ValueEquality.lists(entry.$1, candidates))
      ..add((List.unmodifiable(candidates), page));
  }

  /// The candidates of each [resolve] call, in call order, repeats included.
  List<List<Uri>> get calls => List.unmodifiable(_calls);

  /// The candidates of each request cancelled while pending, in cancel
  /// order. A cancel after the request completed, or a second cancel, is
  /// not recorded: neither changes anything.
  List<List<Uri>> get cancels => List.unmodifiable(_cancels);

  /// How many requests are pending: neither completed nor cancelled.
  int get pendingCount => _inFlight.length;

  @override
  LinkPreviewRequest resolve(List<Uri> candidates) {
    final asked = List<Uri>.unmodifiable(candidates);
    _calls.add(asked);
    if (failure case final failure?) throw failure;
    late final (List<Uri>, LinkPreviewCompleter) entry;
    final completer = LinkPreviewCompleter(
      onCancel: () {
        _inFlight.remove(entry);
        _cancels.add(asked);
      },
    );
    entry = (asked, completer);
    _inFlight.add(entry);
    return completer.request;
  }

  /// Completes every pending request with its scripted answer, oldest
  /// first.
  void completeAll() {
    final inFlight = List.of(_inFlight);
    _inFlight.clear();
    for (final (candidates, completer) in inFlight) {
      completer.complete(_answerFor(candidates));
    }
  }

  LinkPreview? _answerFor(List<Uri> candidates) {
    for (final (scripted, page) in _answers) {
      if (ValueEquality.lists(scripted, candidates)) return page;
    }
    return null;
  }
}
