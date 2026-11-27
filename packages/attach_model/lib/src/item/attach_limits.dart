import 'package:attach_model/src/item/attach_item.dart';
import 'package:meta/meta.dart';

/// The **attach limits**: what the host allows for one open of the picker.
///
/// Injected per open from the host's rights (the chat, the account), never
/// looked up by the picker. The defaults allow everything with the usual
/// 1024-character caption and no file size limit.
@immutable
final class AttachLimits {
  /// Limits; every field has a permissive default.
  const AttachLimits({
    this.allowedKinds = const {
      AttachKind.photo,
      AttachKind.video,
      AttachKind.animation,
      AttachKind.audio,
      AttachKind.file,
    },
    this.singleSelect = false,
    this.captionLength = 1024,
    this.fileSizeLimit,
    this.timerAllowed = true,
    this.scheduleAllowed = true,
    this.groupingAllowed = true,
    this.spoilerAllowed = true,
    this.sendAsFileAllowed = true,
    this.albumSize = defaultAlbumSize,
  }) : assert(captionLength >= 0, 'a caption length is never negative'),
       assert(albumSize >= 1, 'an album holds at least one item');

  /// [albumSize] when the host sets none.
  static const defaultAlbumSize = 10;

  /// The kinds an item may be; a toggle of any other kind is refused.
  final Set<AttachKind> allowedKinds;

  /// Whether only one item may be selected: a toggle replaces it.
  final bool singleSelect;

  /// The longest caption, in code points (the unit of the message length
  /// budget, so an emoji is one and a ZWJ sequence is each of its code
  /// points); a longer one is rejected by the send plan.
  final int captionLength;

  /// The largest file, in bytes; null for none. An item over it is refused.
  final int? fileSizeLimit;

  /// Whether items may carry a self-destruct timer.
  final bool timerAllowed;

  /// Whether a send may be scheduled.
  final bool scheduleAllowed;

  /// Whether items may be sent as send groups.
  final bool groupingAllowed;

  /// Whether items may be hidden under a spoiler.
  final bool spoilerAllowed;

  /// Whether photos and videos may be sent as files.
  final bool sendAsFileAllowed;

  /// The most items one send group (album) holds; the send plan groups at
  /// the smaller of this and the policy's `maxGroupSize`.
  final int albumSize;

  /// A copy with the given fields replaced; [clearFileSizeLimit] lifts the
  /// file size limit.
  AttachLimits copyWith({
    Set<AttachKind>? allowedKinds,
    bool? singleSelect,
    int? captionLength,
    int? fileSizeLimit,
    bool clearFileSizeLimit = false,
    bool? timerAllowed,
    bool? scheduleAllowed,
    bool? groupingAllowed,
    bool? spoilerAllowed,
    bool? sendAsFileAllowed,
    int? albumSize,
  }) => AttachLimits(
    allowedKinds: allowedKinds ?? this.allowedKinds,
    singleSelect: singleSelect ?? this.singleSelect,
    captionLength: captionLength ?? this.captionLength,
    fileSizeLimit: clearFileSizeLimit
        ? null
        : fileSizeLimit ?? this.fileSizeLimit,
    timerAllowed: timerAllowed ?? this.timerAllowed,
    scheduleAllowed: scheduleAllowed ?? this.scheduleAllowed,
    groupingAllowed: groupingAllowed ?? this.groupingAllowed,
    spoilerAllowed: spoilerAllowed ?? this.spoilerAllowed,
    sendAsFileAllowed: sendAsFileAllowed ?? this.sendAsFileAllowed,
    albumSize: albumSize ?? this.albumSize,
  );

  /// Whether [kind] is allowed.
  bool allows(AttachKind kind) => allowedKinds.contains(kind);

  @override
  bool operator ==(Object other) =>
      other is AttachLimits &&
      other.allowedKinds.length == allowedKinds.length &&
      other.allowedKinds.containsAll(allowedKinds) &&
      other.singleSelect == singleSelect &&
      other.captionLength == captionLength &&
      other.fileSizeLimit == fileSizeLimit &&
      other.timerAllowed == timerAllowed &&
      other.scheduleAllowed == scheduleAllowed &&
      other.groupingAllowed == groupingAllowed &&
      other.spoilerAllowed == spoilerAllowed &&
      other.sendAsFileAllowed == sendAsFileAllowed &&
      other.albumSize == albumSize;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(allowedKinds),
    singleSelect,
    captionLength,
    fileSizeLimit,
    timerAllowed,
    scheduleAllowed,
    groupingAllowed,
    spoilerAllowed,
    sendAsFileAllowed,
    albumSize,
  );
}
