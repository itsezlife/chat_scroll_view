import 'package:content_model/src/pack/pack.dart';
import 'package:listen/listen.dart';
import 'package:meta/meta.dart';

/// What a [PackSource] knows about one pack.
///
/// One of five mutually exclusive states:
///
/// - [idle]: never asked for, or not held.
/// - [loading]: a first lookup is in flight.
/// - [PackLookup.found]: the pack.
/// - [notFound]: the source answered that no such pack exists.
/// - [PackLookup.failed]: the last lookup could not be answered.
///
/// [PackSource.lookup] answers only the last three.
@immutable
sealed class PackLookup {
  /// The pack was found.
  const factory PackLookup.found(Pack pack) = PackLookup$Found;

  /// The lookup could not be answered (no connection, a storage error).
  /// [error] and [stackTrace] are diagnostics for the host to log;
  /// [stackTrace] is ignored by equality.
  const factory PackLookup.failed(Object error, [StackTrace? stackTrace]) =
      PackLookup$Failed;

  const PackLookup._();

  /// Never asked for.
  static const PackLookup idle = PackLookup$Idle();

  /// A first lookup is in flight.
  static const PackLookup loading = PackLookup$Loading();

  /// No such pack exists.
  static const PackLookup notFound = PackLookup$NotFound();
}

/// The [PackLookup.idle] state.
final class PackLookup$Idle extends PackLookup {
  /// Creates the idle state.
  const PackLookup$Idle() : super._();

  @override
  bool operator ==(Object other) => other is PackLookup$Idle;

  @override
  int get hashCode => (PackLookup$Idle).hashCode;

  @override
  String toString() => 'PackLookup.idle';
}

/// The [PackLookup.loading] state.
final class PackLookup$Loading extends PackLookup {
  /// Creates the loading state.
  const PackLookup$Loading() : super._();

  @override
  bool operator ==(Object other) => other is PackLookup$Loading;

  @override
  int get hashCode => (PackLookup$Loading).hashCode;

  @override
  String toString() => 'PackLookup.loading';
}

/// The [PackLookup.found] state.
final class PackLookup$Found extends PackLookup {
  /// Creates the found state of [pack].
  const PackLookup$Found(this.pack) : super._();

  /// The pack found.
  final Pack pack;

  @override
  bool operator ==(Object other) =>
      other is PackLookup$Found && other.pack == pack;

  @override
  int get hashCode => Object.hash(PackLookup$Found, pack);

  @override
  String toString() => 'PackLookup.found($pack)';
}

/// The [PackLookup.notFound] state.
final class PackLookup$NotFound extends PackLookup {
  /// Creates the not-found state.
  const PackLookup$NotFound() : super._();

  @override
  bool operator ==(Object other) => other is PackLookup$NotFound;

  @override
  int get hashCode => (PackLookup$NotFound).hashCode;

  @override
  String toString() => 'PackLookup.notFound';
}

/// The [PackLookup.failed] state.
final class PackLookup$Failed extends PackLookup {
  /// Creates the failed state for [error].
  const PackLookup$Failed(this.error, [this.stackTrace]) : super._();

  /// What the lookup failed with.
  final Object error;

  /// Where [error] was thrown, when known.
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) =>
      other is PackLookup$Failed && other.error == error;

  @override
  int get hashCode => Object.hash(PackLookup$Failed, error);

  @override
  String toString() => 'PackLookup.failed($error)';
}

/// Where a pack sheet, a preview or a page gets a [Pack] by its id.
///
/// The host implements the tiers behind it (its own cache, then the remote);
/// a source answers from memory first. A content's pack is named by its
/// descriptor's pack reference, so any content on screen can open its pack.
///
/// ## Answers
///
/// - [lookup] answers `found`, `notFound` or `failed`, and never completes
///   with an error: a failure is an answer.
/// - A pack found is kept for the source's lifetime, installed or not: a pack
///   the user only looked at opens again at once.
/// - `notFound` is kept too; `failed` is not: the next [lookup] tries again.
/// - Lookups of one id while one is in flight share it: one fetch, one answer.
/// - With `refresh`, a held answer is fetched again. [peek] keeps answering
///   the held pack meanwhile (no `loading`); a refresh that fails keeps the
///   held pack and answers it.
///
/// ## Peeking
///
/// [peek] answers at once, without loading: `idle` before any lookup,
/// `loading` while the first is in flight, then the last answer. [changes]
/// signals once each time what [peek] answers for some id changes.
///
/// ## Disposal
///
/// After [dispose], [changes] is silent, [peek] keeps answering the last
/// state, and [lookup] answers [peek] at once, fetching nothing; work in
/// flight is dropped. [dispose] is idempotent.
abstract interface class PackSource {
  /// Signals each time what [peek] answers for some pack changes.
  Listenable get changes;

  /// What is known about [id] now, without loading.
  PackLookup peek(PackId id);

  /// Answers the pack [id]: held, or fetched when not held or when
  /// [refresh] is true.
  Future<PackLookup> lookup(PackId id, {bool refresh = false});

  /// Releases the source and its listeners.
  void dispose();
}
