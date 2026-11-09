import 'package:content_model/content_model.dart';
import 'package:content_model/src/testing/fake_gate.dart';

/// An in-memory [LibraryStorage] for tests.
///
/// Follows the whole seam contract. [edits] records every edit committed, in
/// order, as a backend would receive them; [failure] makes reads and commits
/// fail and leaves the state as it was; [gate] holds commits until the test
/// releases them.
final class FakeLibraryStorage implements LibraryStorage {
  /// Creates a storage holding [state].
  FakeLibraryStorage([LibraryState? state])
    : _state = state ?? LibraryState.empty;

  LibraryState _state;
  final _edits = <LibraryEdit>[];

  /// Holds every commit while paused.
  final gate = FakeGate();

  /// When non-null, every call fails with it.
  Exception? failure;

  /// What was last committed.
  LibraryState get state => _state;

  /// The edits committed, in order. Unmodifiable.
  List<LibraryEdit> get edits => List.unmodifiable(_edits);

  @override
  Future<LibraryState> read() async {
    if (failure case final failure?) throw failure;
    return _state;
  }

  @override
  Future<void> commit(LibraryEdit edit, LibraryState state) async {
    await gate.turn();
    if (failure case final failure?) throw failure;
    _edits.add(edit);
    _state = state;
  }
}
