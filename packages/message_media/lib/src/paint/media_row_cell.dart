import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/layout/media_corner_radii.dart';
import 'package:message_media/src/paint/media_cell_builders.dart';
import 'package:mpx_core/mpx_core.dart';

/// The default file row cell: the file's status control (download,
/// progress, its thumbnail when it has one) at the row's leading edge,
/// drawn through the asset pipeline.
///
/// Interim: the row's own geometry (title, info line, thumbnail sizes,
/// stacking) is the file stack's; this cell draws only the control in a
/// square of [controlExtent], vertically centred.
class MediaRowCell extends StatelessWidget {
  /// A row of [item] sized [size], rounded by [radii].
  const MediaRowCell({
    required this.item,
    required this.size,
    this.radii = MediaCornerRadii.zero,
    this.downloadContext,
    this.controlExtent = 44,
    super.key,
  });

  /// The [MediaCellBuilder] of the default row.
  static Widget builder(BuildContext context, MediaCellData data) =>
      MediaRowCell(
        item: data.item,
        size: data.cell.rect.size,
        radii: data.cell.radii,
        downloadContext: data.downloadContext,
      );

  /// The item drawn.
  final MediaItem item;

  /// The row's size.
  final Size size;

  /// The row's corners.
  final MediaCornerRadii radii;

  /// The class of conversation the file is shown in.
  final AutoDownloadContext? downloadContext;

  /// The side of the control's square.
  final double controlExtent;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(radii.topLeft),
      topRight: Radius.circular(radii.topRight),
      bottomLeft: Radius.circular(radii.bottomLeft),
      bottomRight: Radius.circular(radii.bottomRight),
    ),
    child: SizedBox.fromSize(
      size: size,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(controlExtent / 2),
          child: SizedBox.square(
            dimension: controlExtent,
            child: ContentAssetView(
              content: item.descriptor.key,
              preset: AssetPreset(
                size: Size.square(controlExtent),
                spec: const AssetSpec(pixelWidth: 160, pixelHeight: 160),
                profile: const AssetProfile(fit: AssetFit.cover),
              ),
              status: const MediaStatusMode.control(),
              downloadContext: downloadContext,
            ),
          ),
        ),
      ),
    ),
  );
}
