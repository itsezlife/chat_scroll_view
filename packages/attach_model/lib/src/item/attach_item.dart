import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// What an **attach item** is, as the intake classified it.
///
/// Classification is the intake's: the picker never sniffs bytes. "Send as
/// file" overrides the kind at send (the send plan reads it), not here.
enum AttachKind {
  /// A still image.
  photo,

  /// A video with sound.
  video,

  /// A GIF or a silent looping video. Never grouped with other items.
  animation,

  /// A music or voice file.
  audio,

  /// Any other file, or media picked to go as a document.
  file;

  /// Whether this kind is drawn as media (photo, video, animation) rather
  /// than as a document row.
  bool get isMedia => switch (this) {
    photo || video || animation => true,
    audio || file => false,
  };
}

/// The stable identity of an **attach item** within one open of the picker.
///
/// A nominal string so it is never mixed with a library asset id or a path:
/// the same library asset picked twice is one id, but its id is not the
/// asset id by contract (a source chooses how it derives one).
extension type const AttachItemId(String value) implements String {}

/// Where an **attach item** comes from, by plain values.
///
/// The model takes no media package, so a source names its origin by the
/// value the host's media layer can resolve again: a library asset id, a
/// file path, a web blob handle, or a local key's stable form for media the
/// picker captured or the composer received by paste.
@immutable
sealed class AttachSource {
  const AttachSource._();

  /// An asset of the device media library, by its library id.
  const factory AttachSource.library(String assetId) = AttachSource$Library;

  /// A file on disk, by its path.
  const factory AttachSource.file(String path) = AttachSource$File;

  /// A browser blob, by the handle the web intake gave it.
  const factory AttachSource.blob(String handle) = AttachSource$Blob;

  /// Media the picker's camera captured, by its local key's stable form.
  const factory AttachSource.captured(String localKey) = AttachSource$Captured;

  /// Media pasted into the composer, by its local key's stable form.
  const factory AttachSource.pasted(String localKey) = AttachSource$Pasted;
}

/// [AttachSource.library].
final class AttachSource$Library extends AttachSource {
  /// An asset of the device library.
  const AttachSource$Library(this.assetId) : super._();

  /// The library's id of the asset.
  final String assetId;

  @override
  bool operator ==(Object other) =>
      other is AttachSource$Library && other.assetId == assetId;

  @override
  int get hashCode => Object.hash(AttachSource$Library, assetId);

  @override
  String toString() => 'AttachSource.library($assetId)';
}

/// [AttachSource.file].
final class AttachSource$File extends AttachSource {
  /// A file on disk.
  const AttachSource$File(this.path) : super._();

  /// The file's path.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is AttachSource$File && other.path == path;

  @override
  int get hashCode => Object.hash(AttachSource$File, path);

  @override
  String toString() => 'AttachSource.file($path)';
}

/// [AttachSource.blob].
final class AttachSource$Blob extends AttachSource {
  /// A browser blob.
  const AttachSource$Blob(this.handle) : super._();

  /// The handle the web intake gave the blob.
  final String handle;

  @override
  bool operator ==(Object other) =>
      other is AttachSource$Blob && other.handle == handle;

  @override
  int get hashCode => Object.hash(AttachSource$Blob, handle);

  @override
  String toString() => 'AttachSource.blob($handle)';
}

/// [AttachSource.captured].
final class AttachSource$Captured extends AttachSource {
  /// Captured media.
  const AttachSource$Captured(this.localKey) : super._();

  /// The stable form of the captured media's local key.
  final String localKey;

  @override
  bool operator ==(Object other) =>
      other is AttachSource$Captured && other.localKey == localKey;

  @override
  int get hashCode => Object.hash(AttachSource$Captured, localKey);

  @override
  String toString() => 'AttachSource.captured($localKey)';
}

/// [AttachSource.pasted].
final class AttachSource$Pasted extends AttachSource {
  /// Pasted media.
  const AttachSource$Pasted(this.localKey) : super._();

  /// The stable form of the pasted media's local key.
  final String localKey;

  @override
  bool operator ==(Object other) =>
      other is AttachSource$Pasted && other.localKey == localKey;

  @override
  int get hashCode => Object.hash(AttachSource$Pasted, localKey);

  @override
  String toString() => 'AttachSource.pasted($localKey)';
}

/// A width and a height in pixels.
@immutable
final class AttachDimensions {
  /// Dimensions of [width] by [height].
  const AttachDimensions(this.width, this.height)
    : assert(width >= 0 && height >= 0, 'dimensions are never negative');

  /// The width in pixels.
  final int width;

  /// The height in pixels.
  final int height;

  /// The longer side.
  int get longSide => width > height ? width : height;

  @override
  bool operator ==(Object other) =>
      other is AttachDimensions &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'AttachDimensions($width x $height)';
}

/// What the intake learnt about an item. Every fact may be unknown (null):
/// a file dialog knows a size and a name, a library asset dimensions and a
/// duration.
@immutable
final class AttachFacts {
  /// Facts, each optional.
  const AttachFacts({
    this.byteSize,
    this.dimensions,
    this.duration,
    this.mimeType,
    this.name,
    this.modified,
  });

  /// The size in bytes; checked against the attach limits' file size limit.
  final int? byteSize;

  /// The pixel size of a photo, video or animation.
  final AttachDimensions? dimensions;

  /// The running time of a video, animation or audio file.
  final Duration? duration;

  /// The MIME type.
  final String? mimeType;

  /// The file name shown for a document row.
  final String? name;

  /// When the source was last modified.
  final DateTime? modified;

  @override
  bool operator ==(Object other) =>
      other is AttachFacts &&
      other.byteSize == byteSize &&
      other.dimensions == dimensions &&
      other.duration == duration &&
      other.mimeType == mimeType &&
      other.name == name &&
      other.modified == modified;

  @override
  int get hashCode =>
      Object.hash(byteSize, dimensions, duration, mimeType, name, modified);
}

/// A self-destruct timer on one item: seen once, or gone a while after it
/// is opened.
///
/// An item with a timer is never grouped and cannot be scheduled; the send
/// plan enforces both.
@immutable
final class AttachTimer {
  /// Gone after it is viewed once.
  const AttachTimer.once() : after = null;

  /// Gone [after] it is opened.
  const AttachTimer.after(Duration this.after);

  /// The time after opening; null for [AttachTimer.once].
  final Duration? after;

  /// Whether this is [AttachTimer.once].
  bool get isOnce => after == null;

  @override
  bool operator ==(Object other) =>
      other is AttachTimer && other.after == after;

  @override
  int get hashCode => Object.hash(AttachTimer, after);

  @override
  String toString() =>
      isOnce ? 'AttachTimer.once()' : 'AttachTimer.after($after)';
}

/// An editor's recipe for an **edited item**: opaque to the model.
///
/// The editor that wrote it reads it back; [version] lets it migrate or
/// drop a recipe it no longer knows. No editor ships in v1, so nothing
/// writes one yet; the slot is reserved so an editor adds a writer and no
/// model change.
@immutable
final class ItemEdits {
  /// A recipe of the editor's [version].
  const ItemEdits({required this.version, required this.recipe});

  /// The recipe's schema version, the editor's own.
  final int version;

  /// The recipe, in the editor's own form. Compared by `==`.
  final Object recipe;

  @override
  bool operator ==(Object other) =>
      other is ItemEdits && other.version == version && other.recipe == recipe;

  @override
  int get hashCode => Object.hash(version, recipe);
}

/// The output an editor rendered for an **edited item**: what the send plan
/// and preparation read in place of the source.
@immutable
final class DerivedOutput {
  /// An output at [localKey].
  const DerivedOutput({
    required this.localKey,
    this.dimensions,
    this.duration,
    this.muted = false,
    this.animated = false,
  });

  /// The stable form of the rendered output's local key.
  final String localKey;

  /// The rendered pixel size.
  final AttachDimensions? dimensions;

  /// The rendered running time (a trimmed video).
  final Duration? duration;

  /// Whether the rendered video has no sound.
  final bool muted;

  /// Whether the output is an animation (a painted scene that moves).
  final bool animated;

  @override
  bool operator ==(Object other) =>
      other is DerivedOutput &&
      other.localKey == localKey &&
      other.dimensions == dimensions &&
      other.duration == duration &&
      other.muted == muted &&
      other.animated == animated;

  @override
  int get hashCode =>
      Object.hash(localKey, dimensions, duration, muted, animated);
}

/// One **attach item**: a thing picked to send, its kind, facts and the
/// per-item state the user set on it.
///
/// Per-item state (spoiler, timer, caption, edits, derived output) travels
/// with the item, so reordering the attach selection keeps it.
@immutable
final class AttachItem {
  /// An item of [kind] from [source].
  const AttachItem({
    required this.id,
    required this.source,
    required this.kind,
    this.facts = const AttachFacts(),
    this.spoiler = false,
    this.timer,
    this.caption,
    this.edits,
    this.derived,
  });

  /// The item's identity in the attach selection.
  final AttachItemId id;

  /// Where the item comes from.
  final AttachSource source;

  /// What the intake classified it as.
  final AttachKind kind;

  /// What the intake learnt about the source.
  final AttachFacts facts;

  /// Whether the item is hidden under a spoiler. A per-item flag inside a
  /// send group; it never breaks one.
  final bool spoiler;

  /// The item's self-destruct timer, if any.
  final AttachTimer? timer;

  /// The item's own caption, apart from the batch caption.
  final RichText? caption;

  /// The editor's recipe, when the item is an edited item.
  final ItemEdits? edits;

  /// The editor's rendered output, read in place of the source.
  final DerivedOutput? derived;

  /// Whether an editor touched this item.
  bool get isEdited => edits != null || derived != null;

  /// The pixel size to send: the derived output's when present.
  AttachDimensions? get effectiveDimensions =>
      derived?.dimensions ?? facts.dimensions;

  /// The running time to send: the derived output's when present.
  Duration? get effectiveDuration => derived?.duration ?? facts.duration;

  /// Whether the item sends as an animation: its kind, or a derived output
  /// that moves.
  bool get isAnimated =>
      kind == AttachKind.animation || (derived?.animated ?? false);

  /// Whether the item sends as a video with no sound (from its derived
  /// output; the intake's silent videos are already [AttachKind.animation]).
  bool get isMuted => derived?.muted ?? false;

  /// A copy with the named fields replaced. [timer], [caption], [edits] and
  /// [derived] are cleared by passing [clearTimer], [clearCaption],
  /// [clearEdits] and [clearDerived].
  AttachItem copyWith({
    AttachKind? kind,
    AttachFacts? facts,
    bool? spoiler,
    AttachTimer? timer,
    bool clearTimer = false,
    RichText? caption,
    bool clearCaption = false,
    ItemEdits? edits,
    bool clearEdits = false,
    DerivedOutput? derived,
    bool clearDerived = false,
  }) => AttachItem(
    id: id,
    source: source,
    kind: kind ?? this.kind,
    facts: facts ?? this.facts,
    spoiler: spoiler ?? this.spoiler,
    timer: clearTimer ? null : timer ?? this.timer,
    caption: clearCaption ? null : caption ?? this.caption,
    edits: clearEdits ? null : edits ?? this.edits,
    derived: clearDerived ? null : derived ?? this.derived,
  );

  @override
  bool operator ==(Object other) =>
      other is AttachItem &&
      other.id == id &&
      other.source == source &&
      other.kind == kind &&
      other.facts == facts &&
      other.spoiler == spoiler &&
      other.timer == timer &&
      other.caption == caption &&
      other.edits == edits &&
      other.derived == derived;

  @override
  int get hashCode => Object.hash(
    id,
    source,
    kind,
    facts,
    spoiler,
    timer,
    caption,
    edits,
    derived,
  );

  @override
  String toString() => 'AttachItem($id, ${kind.name})';
}
