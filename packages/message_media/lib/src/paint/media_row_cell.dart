import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/layout/media_corner_radii.dart';
import 'package:message_media/src/layout/media_file_row.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:message_media/src/layout/media_layout_text.dart';
import 'package:message_media/src/paint/media_box_cell.dart';
import 'package:message_media/src/paint/media_cell_builders.dart';
import 'package:message_media/src/paint/media_file_disc.dart';
import 'package:message_media/src/paint/middle_elided_text.dart';
import 'package:message_media/src/policy/media_file_stack_policy.dart';
import 'package:mpx_core/mpx_core.dart';

/// The default file row cell: the file disc ([MediaFileDisc]) under the
/// status control, or the thumbnail with the control centred on it, the name, the info line and, where the platform
/// draws one, the link line, each where the file stack laid it out
/// ([MediaFileRow]).
///
/// ## Drawing
///
/// The control and the thumbnail draw through the asset pipeline
/// (`ContentAssetView`), so they show the loading stages and the status
/// control of the media core. The name is cut in the middle to the lines the
/// layout gave it ([MiddleElidedText]), with the full name in a tooltip where
/// the policy says so. The info line shows the size at rest and the bytes
/// received of the total while they arrive, both worded by the host's media
/// strings. Text is drawn in the [MediaLayoutText] the layout measured with
/// (the chrome typography at the policy's sizes, under the platform's text
/// scaler); colours come from the ambient text colour unless given.
///
/// ## Right to left
///
/// A row whose policy mirrors it ([MediaFileRow.mirrorsInRtl]) is flipped in
/// a right-to-left list: the control at the right, the text aligned right.
/// Other rows keep their left-to-right layout in every list.
class MediaRowCell extends StatelessWidget {
  /// A row of [item] sized [size], laid out as [row].
  const MediaRowCell({
    required this.item,
    required this.size,
    required this.row,
    this.policy = const MediaFileStackPolicy.android(),
    this.radii = MediaCornerRadii.zero,
    this.neighbours = MediaNeighbours.bubble,
    this.downloadContext,
    this.nameColor,
    this.infoColor,
    this.linkColor,
    this.discColor,
    this.skin,
    super.key,
  });

  /// The [MediaCellBuilder] of the default row.
  ///
  /// A layout step that reported no row geometry (a host's own step) gets
  /// the policy's row for the cell's width.
  static Widget builder(BuildContext context, MediaCellData data) =>
      MediaRowCell(
        item: data.item,
        size: data.cell.rect.size,
        row: rowOf(context, data),
        policy: data.fileStack ?? const MediaFileStackPolicy.android(),
        radii: data.cell.radii,
        neighbours: data.cell.neighbours,
        downloadContext: data.downloadContext,
        skin: MediaBoxCell.skinOf(data),
      );

  /// The row geometry the default row of [data] draws by: the layout's, or,
  /// when the layout step reported none, the policy's row for the cell's
  /// width.
  static MediaFileRow rowOf(BuildContext context, MediaCellData data) {
    if (data.fileRow case final row?) return row;
    final policy = data.fileStack ?? const MediaFileStackPolicy.android();
    return policy
        .layout(
          [data.item],
          MediaLayoutInput(
            items: [data.item],
            availableWidth: data.cell.rect.width,
            text: MediaLayoutText.of(context),
          ),
          top: 0,
          topSide: data.cell.neighbours.top,
          bottomSide: data.cell.neighbours.bottom,
          isLastBlock: false,
        )
        .rows
        .single;
  }

  /// The item drawn.
  final MediaItem item;

  /// The row's size.
  final Size size;

  /// The row's laid-out geometry.
  final MediaFileRow row;

  /// The file rows' policy: type, thumbnail corners.
  final MediaFileStackPolicy policy;

  /// The row's corners.
  final MediaCornerRadii radii;

  /// What the row's sides touch, which a thumbnail's corners may follow.
  final MediaNeighbours neighbours;

  /// The class of conversation the file is shown in.
  final AutoDownloadContext? downloadContext;

  /// The name's colour; null is the ambient text colour.
  final Color? nameColor;

  /// The info line's colour; null is the ambient text colour at 60 %.
  final Color? infoColor;

  /// The link line's colour; null is the name's.
  final Color? linkColor;

  /// The fill of the file disc a row without a picture draws
  /// ([MediaFileDisc]); null is the chrome palette's accent.
  final Color? discColor;

  /// The look of the row's status control (the policy's chrome slots, the
  /// sent check, none on a failed send); null keeps the loading style's.
  final AssetViewSkin? skin;

  /// The preset the row's control attaches with: the view's own binding of
  /// the item uses the same, so the two share one cache entry.
  static AssetPreset presetOf(MediaFileRow row) => AssetPreset(
    size: row.leading.size,
    spec: AssetSpec(
      pixelWidth: (row.leading.width * 3).round(),
      pixelHeight: (row.leading.height * 3).round(),
    ),
    profile: const AssetProfile(fit: AssetFit.cover),
  );

  @override
  Widget build(BuildContext context) {
    final mirrored =
        row.mirrorsInRtl && Directionality.of(context) == TextDirection.rtl;
    Rect place(Rect rect) => mirrored
        ? Rect.fromLTWH(
            size.width - rect.right,
            rect.top,
            rect.width,
            rect.height,
          )
        : rect;
    final type = MediaLayoutText.of(context);
    final base = type.style;
    final strings = type.strings;
    final ambient = DefaultTextStyle.of(context).style.color;
    final nameColor = this.nameColor ?? ambient ?? const Color(0xFF000000);
    final infoColor =
        this.infoColor ?? nameColor.withValues(alpha: nameColor.a * 0.6);
    final nameStyle = policy.text.nameOver(base).copyWith(color: nameColor);
    final infoStyle = policy.text.infoOver(base).copyWith(color: infoColor);
    final linkStyle = policy.text
        .infoOver(base)
        .copyWith(color: linkColor ?? nameColor);
    final align = mirrored ? TextAlign.right : TextAlign.left;
    final preset = presetOf(row);
    return ClipRRect(
      borderRadius: _border(radii, mirrored: false),
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: place(row.leading),
              child: ClipRRect(
                borderRadius: row.hasThumbnail
                    ? _border(
                        policy.thumbCorners.radiiOf(radii, neighbours),
                        mirrored: mirrored,
                      )
                    : BorderRadius.circular(row.leading.shortestSide / 2),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // A file without a picture shows the file disc, the
                    // control over it while the bytes are not here.
                    if (!row.hasThumbnail)
                      MediaFileDisc(
                        color:
                            discColor ??
                            ChromeThemeScope.paletteOf(context).accent,
                      ),
                    // The control takes no pointer: its taps are the view's
                    // body part hits (`MediaPart.status`), arbitrated by the
                    // viewport.
                    IgnorePointer(
                      child: ContentAssetView(
                        content: item.descriptor.key,
                        preset: preset,
                        status: const MediaStatusMode.control(),
                        downloadContext: downloadContext,
                        skin: skin,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fromRect(
              rect: place(row.name),
              child: MiddleElidedText(
                item.descriptor.fileName ?? '',
                style: nameStyle,
                maxLines: row.nameLines,
                textAlign: align,
                tooltipWhenElided: policy.tooltipWhenElided,
                textScaler: type.scaler,
              ),
            ),
            Positioned.fill(
              child: AssetLoadStateBuilder(
                content: item.descriptor.key.mediaKey,
                preset: preset,
                scope: ContentAssetProvider.maybeOf(context)?.media,
                downloadContext: downloadContext,
                builder: (context, state, _) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fromRect(
                      rect: place(row.info),
                      child: Text(
                        _infoOf(state, strings),
                        style: infoStyle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        textAlign: align,
                        textScaler: type.scaler,
                      ),
                    ),
                    if (row.link case final link?)
                      Positioned.fromRect(
                        rect: place(link),
                        child: Text(
                          _linkOf(state, strings),
                          style: linkStyle,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: align,
                          textScaler: type.scaler,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The info line: the bytes received of the total while they arrive, the
  /// row's resting text otherwise.
  String _infoOf(AssetLoadState state, MediaStrings strings) =>
      switch (state.transfer) {
        AssetTransfer$Receiving(:final received, total: final total?) =>
          strings.fileProgress(strings.size(received), strings.size(total)),
        _ => row.infoText,
      };

  String _linkOf(AssetLoadState state, MediaStrings strings) => switch (state) {
    AssetLoadState(:final transfer) when transfer.isActive =>
      strings.fileCancel,
    AssetLoadState(shown: true) => strings.fileOpenWith,
    _ => strings.fileDownload,
  };

  static BorderRadius _border(
    MediaCornerRadii radii, {
    required bool mirrored,
  }) => mirrored
      ? BorderRadius.only(
          topLeft: Radius.circular(radii.topRight),
          topRight: Radius.circular(radii.topLeft),
          bottomLeft: Radius.circular(radii.bottomRight),
          bottomRight: Radius.circular(radii.bottomLeft),
        )
      : BorderRadius.only(
          topLeft: Radius.circular(radii.topLeft),
          topRight: Radius.circular(radii.topRight),
          bottomLeft: Radius.circular(radii.bottomLeft),
          bottomRight: Radius.circular(radii.bottomRight),
        );
}
