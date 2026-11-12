import 'dart:convert';

import 'package:content_model/content_model.dart';
import 'package:l/l.dart';

/// A pack the app ships, by its id and kind.
typedef ShippedPack = ({PackId id, PackKind kind});

/// Installs the packs the app ships, each once in the life of the install.
///
/// The panel lists the user's installed packs, not every pack the app knows,
/// so a first run would show none. This stands in for the server's default
/// packs: every shipped pack the store has not seen is installed, in the
/// shipped order, and remembered. A pack the user removes later stays
/// removed; a pack shipped by a later version (a new corpus folder) is
/// installed on the next run.
///
/// A loaded store like the others: [load] reads what was seen with the
/// other stores, before any source reads the catalogue, and [install] runs
/// once the packs are known. The seen ids are one JSON list under
/// [namespace] / [key].
final class ShippedPacksSeed {
  ShippedPacksSeed._(this._store, this._seen);

  /// The key-value namespace the seen ids are kept in.
  static const String namespace = 'library_seed';

  /// The key of the seen ids.
  static const String key = 'packs';

  static const int _version = 1;

  final KeyValueStore? _store;
  final Set<String> _seen;

  /// Reads which packs [store] has seen.
  ///
  /// A store that cannot be read seeds nothing: the seed is a convenience
  /// of the demo, not worth failing the boot for, and installing again what
  /// the user removed would be worse than installing nothing.
  static Future<ShippedPacksSeed> load(KeyValueStore store) async {
    try {
      return ShippedPacksSeed._(
        store,
        _decode(await store.read(namespace, key)),
      );
    } on Object catch (error, stack) {
      l.w('The shipped packs are not installed: $error', stack);
      return ShippedPacksSeed._(null, const {});
    }
  }

  /// Installs the packs of [shipped] not seen yet into [library], in order,
  /// and records them as seen.
  Future<void> install(
    ContentLibrary library,
    List<ShippedPack> shipped,
  ) async {
    final store = _store;
    if (store == null) return;
    final fresh = [
      for (final pack in shipped)
        if (!_seen.contains(pack.id.value)) pack,
    ];
    if (fresh.isEmpty) return;
    // Installing puts a pack first: the last one goes in first, so the
    // shipped order is the order shown.
    for (final pack in fresh.reversed) {
      library.apply(LibraryEdit.installPack(pack.id, pack.kind));
    }
    _seen.addAll([for (final pack in fresh) pack.id.value]);
    try {
      await store.write(
        namespace,
        key,
        StoredValue(jsonEncode(_seen.toList()), version: _version),
      );
    } on Object catch (error, stack) {
      l.w('The shipped packs were not recorded: $error', stack);
    }
  }

  static Set<String> _decode(StoredValue? stored) => switch (stored) {
    StoredValue(:final value, version: _version) => switch (jsonDecode(value)) {
      final List<Object?> ids => {...ids.whereType<String>()},
      _ => <String>{},
    },
    _ => <String>{},
  };
}
