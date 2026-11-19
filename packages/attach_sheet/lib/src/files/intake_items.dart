import 'package:attach_model/attach_model.dart';
import 'package:mpx_library/mpx_library.dart';

/// Maps the file intake's files to attach items, and keeps each item's
/// intake file so the host can read it back at send.
///
/// A browser blob has no stable value of its own; its attach source names
/// it by the file's dedup facts, and [fileOf] returns the blob's file.
final class IntakeItems {
  final Map<AttachItemId, IntakeFile> _$files = {};

  /// The attach item of [file]: as a file (or audio) when [asMedia] is
  /// false, else by its classified kind.
  AttachItem itemOf(IntakeFile file, {required bool asMedia}) {
    final kind = switch (IntakeKind.classify(
      mimeType: file.mimeType,
      name: file.name,
    )) {
      IntakeKind.audio => AttachKind.audio,
      IntakeKind.photo when asMedia => AttachKind.photo,
      IntakeKind.video when asMedia => AttachKind.video,
      IntakeKind.animation when asMedia => AttachKind.animation,
      _ => AttachKind.file,
    };
    final (id, source) = switch (file.source) {
      IntakeSource$Path(:final path) => (
        AttachItemId('file:$path'),
        AttachSource.file(path),
      ),
      IntakeSource$Blob() => (
        AttachItemId('blob:${_factsOf(file)}'),
        AttachSource.blob(_factsOf(file)),
      ),
    };
    _$files[id] = file;
    return AttachItem(
      id: id,
      source: source,
      kind: kind,
      facts: AttachFacts(
        byteSize: file.size,
        mimeType: file.mimeType,
        name: file.name,
        modified: file.modified,
      ),
    );
  }

  /// The intake file behind [id], when it came from here.
  IntakeFile? fileOf(AttachItemId id) => _$files[id];

  static String _factsOf(IntakeFile file) =>
      '${file.name}:${file.size}:${file.modified?.microsecondsSinceEpoch ?? ''}';
}
