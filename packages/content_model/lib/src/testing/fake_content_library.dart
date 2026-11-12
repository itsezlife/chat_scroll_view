import 'package:content_model/content_model.dart';
import 'package:content_model/src/store/library_ledger.dart';
import 'package:listen/listen.dart';

/// An in-memory [ContentLibrary] for tests, created at once with nothing to
/// load.
///
/// Follows the whole seam contract. [committed] records the edits that
/// reached its storage, in order; [failure] makes commits fail. Use it to
/// drive a page, a sheet or a host; use the reference library over a
/// `FakeLibraryStorage` when the test is about what reaches storage.
final class FakeContentLibrary implements ContentLibrary {
  /// Creates a library holding [initial], kept to [limits].
  FakeContentLibrary({required LibraryLimits limits, LibraryState? initial}) {
    _ledger = LibraryLedger(
      committed: initial ?? LibraryState.empty,
      limits: limits,
      commit: _commit,
    );
  }

  late final LibraryLedger _ledger;
  final _committed = <LibraryEdit>[];

  /// When non-null, every commit fails with it.
  Exception? failure;

  /// The edits committed, in order. Unmodifiable.
  List<LibraryEdit> get committed => List.unmodifiable(_committed);

  Future<void> _commit(LibraryEdit edit, LibraryState state) async {
    if (failure case final failure?) throw failure;
    _committed.add(edit);
  }

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
