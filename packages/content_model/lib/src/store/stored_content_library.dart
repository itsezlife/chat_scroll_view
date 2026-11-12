import 'package:content_model/src/data/content_library.dart';
import 'package:content_model/src/data/library_storage.dart';
import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/pack/pack.dart';
import 'package:content_model/src/store/library_ledger.dart';
import 'package:listen/listen.dart';

/// The reference [ContentLibrary]: the lists in memory, committed through a
/// [LibraryStorage].
///
/// Obtained only through [load], which reads the storage first, so there is
/// no unloaded library whose first edits could be lost or overwritten. Lists
/// read back longer than [limits] are cut to them (a lower limit than when
/// they were written); the cut reaches storage with the next commit.
///
/// Every rule is the [ContentLibrary] contract's. Storage sees the committed
/// edits one at a time, in the order they were applied, each with the
/// committed state after it; a failed commit leaves the change in the lists
/// and is reported by its [AppliedEdit.outcome].
final class StoredContentLibrary implements ContentLibrary {
  StoredContentLibrary._(this._ledger);

  /// Creates the library over [storage], reading what it holds first.
  ///
  /// The returned future fails when [storage] cannot be read.
  static Future<StoredContentLibrary> load(
    LibraryStorage storage, {
    required LibraryLimits limits,
  }) async {
    final committed = await storage.read();
    return StoredContentLibrary._(
      LibraryLedger(
        committed: committed,
        limits: limits,
        commit: storage.commit,
      ),
    );
  }

  final LibraryLedger _ledger;

  @override
  LibraryLimits get limits => _ledger.limits;

  @override
  ValueListenable<List<ContentKey>> get recentStickers =>
      _ledger.recentStickers;

  @override
  ValueListenable<List<ContentKey>> get favouriteStickers =>
      _ledger.favouriteStickers;

  @override
  ValueListenable<List<ContentKey>> get savedGifs => _ledger.savedGifs;

  @override
  ValueListenable<List<PackId>> installedPacks(PackKind kind) =>
      _ledger.installedPacks(kind);

  @override
  ValueListenable<List<PackId>> archivedPacks(PackKind kind) =>
      _ledger.archivedPacks(kind);

  @override
  PackInstallState installStateOf(PackId id) => _ledger.installStateOf(id);

  @override
  AppliedEdit apply(LibraryEdit edit, {Duration undoWindow = Duration.zero}) =>
      _ledger.apply(edit, undoWindow: undoWindow);

  @override
  void dispose() => _ledger.dispose();
}
