import 'dart:async';

import 'package:content_model/src/data/pack_source.dart';
import 'package:content_model/src/pack/pack.dart';
import 'package:listen/listen.dart';

/// Fetches the pack [id] from the host's tiers below memory (its own cache,
/// then the remote): the pack, null when no such pack exists, or an error when
/// it could not be answered.
typedef PackFetch = Future<Pack?> Function(PackId id);

/// The reference [PackSource]: the memory tier and the merging of concurrent
/// lookups, over a host [PackFetch].
///
/// Every answer of the seam contract is held here; the host's fetch is asked
/// only for an id not held, a held failure, or a refresh. A fetch that serves
/// a pack of another id is a host error, answered as `failed`.
final class CachingPackSource with ChangeNotifier implements PackSource {
  /// Creates a source over [fetch], holding nothing yet.
  CachingPackSource(PackFetch fetch) : _fetch = fetch;

  final PackFetch _fetch;
  final _held = <PackId, PackLookup>{};
  final _$inFlight = <PackId, Future<PackLookup>>{};
  var _$disposed = false;

  @override
  Listenable get changes => this;

  @override
  PackLookup peek(PackId id) => _held[id] ?? PackLookup.idle;

  @override
  Future<PackLookup> lookup(PackId id, {bool refresh = false}) {
    final held = peek(id);
    if (_$disposed) return Future.value(held);
    if (_$inFlight[id] case final pending?) return pending;
    final answered = switch (held) {
      PackLookup$Found() || PackLookup$NotFound() => true,
      _ => false,
    };
    if (answered && !refresh) return Future.value(held);
    if (!answered) _publish(id, PackLookup.loading);
    final pending = _load(id, held);
    _$inFlight[id] = pending;
    return pending;
  }

  Future<PackLookup> _load(PackId id, PackLookup held) async {
    PackLookup answer;
    try {
      answer = switch (await _fetch(id)) {
        null => PackLookup.notFound,
        final pack when pack.id == id => PackLookup.found(pack),
        final pack => PackLookup.failed(
          StateError('asked for pack ${id.value}, served ${pack.id.value}'),
        ),
      };
    } on Object catch (error, stackTrace) {
      answer = PackLookup.failed(error, stackTrace);
    }
    // A refresh that fails keeps what was held: the user still sees the pack.
    if ((answer, held) case (
      PackLookup$Failed(),
      final PackLookup$Found kept,
    )) {
      answer = kept;
    }
    if (_$disposed) return answer;
    unawaited(_$inFlight.remove(id));
    _publish(id, answer);
    return answer;
  }

  void _publish(PackId id, PackLookup lookup) {
    if (peek(id) == lookup) return;
    _held[id] = lookup;
    notifyListeners();
  }

  // Idempotent: ChangeNotifier asserts on a second dispose, the seam does not.
  @override
  void dispose() {
    if (_$disposed) return;
    _$disposed = true;
    _$inFlight.clear();
    super.dispose();
  }
}
