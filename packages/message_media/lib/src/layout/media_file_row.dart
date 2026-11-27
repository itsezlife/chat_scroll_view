import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// One file row of a file stack laid out: where its leading control or
/// thumbnail, its name, its info line and its link line sit, and where its
/// caption goes.
///
/// Every rect but [captionSlot] is in the row's own coordinates (origin at
/// its cell's top left) and physical (left to right); a row that
/// [mirrorsInRtl] is flipped by the paint step in a right-to-left list.
@immutable
final class MediaFileRow {
  /// The row of [itemId].
  const MediaFileRow({
    required this.itemId,
    required this.hasThumbnail,
    required this.leading,
    required this.control,
    required this.name,
    required this.nameLines,
    required this.info,
    required this.infoText,
    this.link,
    this.captionSlot,
    this.carriesTime = false,
    this.mirrorsInRtl = false,
  }) : assert(nameLines >= 1, 'A name takes at least one line.');

  /// The item the row draws.
  final MediaItemId itemId;

  /// Whether the row draws a thumbnail (else the status control alone).
  final bool hasThumbnail;

  /// The thumbnail's rect, or the status control's without a thumbnail.
  final Rect leading;

  /// The status control's rect: [leading] itself, or centred on the
  /// thumbnail.
  final Rect control;

  /// The name's box: its left, its top, the width it wraps at and the
  /// height of its [nameLines].
  final Rect name;

  /// The lines the name takes; a longer name is elided in the middle to
  /// fit them.
  final int nameLines;

  /// The info line's box.
  final Rect info;

  /// The info line at rest: the size and, where the policy shows it, the
  /// extension (`"1.2 MB PDF"`); while bytes arrive the paint step shows
  /// the progress instead.
  final String infoText;

  /// The link line's box (download, open, cancel), on the platforms that
  /// draw one; null otherwise.
  final Rect? link;

  /// Where the item's own caption goes, in layout coordinates: under the
  /// row, the stack's width and the caption's measured height; null when
  /// the item has no caption of its own.
  final Rect? captionSlot;

  /// Whether the message's time sits on this row (the last file).
  final bool carriesTime;

  /// Whether the row is drawn mirrored in a right-to-left list.
  final bool mirrorsInRtl;

  @override
  bool operator ==(Object other) =>
      other is MediaFileRow &&
      other.itemId == itemId &&
      other.hasThumbnail == hasThumbnail &&
      other.leading == leading &&
      other.control == control &&
      other.name == name &&
      other.nameLines == nameLines &&
      other.info == info &&
      other.infoText == infoText &&
      other.link == link &&
      other.captionSlot == captionSlot &&
      other.carriesTime == carriesTime &&
      other.mirrorsInRtl == mirrorsInRtl;

  @override
  int get hashCode => Object.hash(
    itemId,
    hasThumbnail,
    leading,
    control,
    name,
    nameLines,
    info,
    infoText,
    link,
    captionSlot,
    carriesTime,
    mirrorsInRtl,
  );

  @override
  String toString() =>
      'MediaFileRow($itemId, thumbnail: $hasThumbnail, lines: $nameLines)';
}
