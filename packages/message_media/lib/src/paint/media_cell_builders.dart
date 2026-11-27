import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/chrome/media_chrome_slots.dart';
import 'package:message_media/src/layout/media_file_row.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/paint/media_box_cell.dart';
import 'package:message_media/src/paint/media_row_cell.dart';
import 'package:message_media/src/policy/media_file_stack_policy.dart';
import 'package:message_media/src/policy/media_layout_policy.dart';
import 'package:message_media/src/policy/message_media_policy.dart';
import 'package:mpx_core/mpx_core.dart';

/// What a cell builder draws: one laid-out cell and its item.
@immutable
final class MediaCellData {
  /// The [cell] of [item] in [block].
  const MediaCellData({
    required this.cell,
    required this.item,
    required this.block,
    required this.family,
    required this.autoplay,
    this.downloadContext,
    this.fileRow,
    this.fileStack,
    this.chrome,
    this.correlation = ChatCorrelation.none,
  });

  /// The cell: rect, fit, neighbours and resolved corner radii.
  final MediaCell cell;

  /// The item the cell draws.
  final MediaItem item;

  /// The block the cell sits in.
  final MediaBlock block;

  /// The platform family of the policy that laid it out.
  final MessageMediaPlatform family;

  /// Whether the cell plays inline, muted (the policy's autoplay for this
  /// cell).
  final bool autoplay;

  /// The class of conversation the media is shown in, which the scope's
  /// auto-download rules weigh.
  final AutoDownloadContext? downloadContext;

  /// A file row's laid-out geometry; null for a box, or a row whose layout
  /// step reported none.
  final MediaFileRow? fileRow;

  /// The file rows' policy (type, strings, corners, mirroring) a row cell
  /// draws by; null for a box.
  final MediaFileStackPolicy? fileStack;

  /// The policy's chrome slots, whose info badge and status control a box
  /// draws; null keeps the stock parts.
  final MediaChromeSlots? chrome;

  /// The ids a slot's failure names.
  final ChatCorrelation correlation;

  @override
  bool operator ==(Object other) =>
      other is MediaCellData &&
      other.cell == cell &&
      other.item == item &&
      other.block == block &&
      other.family == family &&
      other.autoplay == autoplay &&
      other.downloadContext == downloadContext &&
      other.fileRow == fileRow &&
      other.fileStack == fileStack &&
      other.chrome == chrome &&
      other.correlation == correlation;

  @override
  int get hashCode => Object.hash(
    cell,
    item,
    block,
    family,
    autoplay,
    downloadContext,
    fileRow,
    fileStack,
    chrome,
    correlation,
  );
}

/// Builds the widget of one cell, sized to the cell's rect by the view.
typedef MediaCellBuilder =
    Widget Function(BuildContext context, MediaCellData data);

/// The cell builders of a message media policy, one per shape, each
/// replaceable on its own.
///
/// | Builder | Kinds | Default |
/// | --- | --- | --- |
/// | [box] | photo, video, animation | [MediaBoxCell] |
/// | [row] | file and custom kinds | [MediaRowCell] |
@immutable
final class MediaCellBuilders {
  /// The given builders; each defaults to the package's own.
  const MediaCellBuilders({
    this.box = MediaBoxCell.builder,
    this.row = MediaRowCell.builder,
  });

  /// Builds a box (photo, video, animation).
  final MediaCellBuilder box;

  /// Builds a file row (file and custom kinds).
  final MediaCellBuilder row;

  /// The builder of a cell of [kind].
  MediaCellBuilder of(MediaItemKind kind) =>
      MediaLayoutPolicy.isBox(kind) ? box : row;

  /// A copy with the given builders replaced.
  MediaCellBuilders copyWith({MediaCellBuilder? box, MediaCellBuilder? row}) =>
      MediaCellBuilders(box: box ?? this.box, row: row ?? this.row);

  @override
  bool operator ==(Object other) =>
      other is MediaCellBuilders && other.box == box && other.row == row;

  @override
  int get hashCode => Object.hash(box, row);
}
