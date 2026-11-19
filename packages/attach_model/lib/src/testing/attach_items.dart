import 'package:attach_model/src/item/attach_item.dart';

/// Ready-made attach items for tests: one factory per kind, each from a
/// library or file source named after its id.
abstract final class AttachItems {
  /// A photo from the library, [width] by [height].
  static AttachItem photo(
    String id, {
    int width = 1280,
    int height = 960,
    bool spoiler = false,
    AttachTimer? timer,
  }) => AttachItem(
    id: AttachItemId(id),
    source: AttachSource.library(id),
    kind: AttachKind.photo,
    facts: AttachFacts(dimensions: AttachDimensions(width, height)),
    spoiler: spoiler,
    timer: timer,
  );

  /// A video with sound from the library.
  static AttachItem video(
    String id, {
    bool spoiler = false,
    AttachTimer? timer,
    DerivedOutput? derived,
  }) => AttachItem(
    id: AttachItemId(id),
    source: AttachSource.library(id),
    kind: AttachKind.video,
    facts: const AttachFacts(
      dimensions: AttachDimensions(1920, 1080),
      duration: Duration(seconds: 12),
    ),
    spoiler: spoiler,
    timer: timer,
    derived: derived,
  );

  /// A GIF from the library.
  static AttachItem animation(String id) => AttachItem(
    id: AttachItemId(id),
    source: AttachSource.library(id),
    kind: AttachKind.animation,
    facts: const AttachFacts(dimensions: AttachDimensions(480, 270)),
  );

  /// A music file.
  static AttachItem audio(String id) => AttachItem(
    id: AttachItemId(id),
    source: AttachSource.file('/music/$id.mp3'),
    kind: AttachKind.audio,
    facts: AttachFacts(name: '$id.mp3', byteSize: 4000000),
  );

  /// A document of [byteSize] bytes.
  static AttachItem file(String id, {int byteSize = 1000}) => AttachItem(
    id: AttachItemId(id),
    source: AttachSource.file('/files/$id.pdf'),
    kind: AttachKind.file,
    facts: AttachFacts(name: '$id.pdf', byteSize: byteSize),
  );
}
