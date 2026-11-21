import 'dart:async';
import 'dart:math' as math;

import 'package:attach_sheet/src/header/attach_selection_header.dart';
import 'package:attach_sheet/src/policy/attach_selection_header_style.dart';
import 'package:attach_sheet/src/sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// The parts a Gallery header is built from: the header's behaviour, the
/// album switcher and the overflow button.
///
/// A host's `GalleryPage` header builder gets them and lays them out as it
/// likes; the stock skins ([AttachSelectionHeader], [AttachPinnedItems]) do
/// the same.
@immutable
final class GalleryHeaderParts {
  /// The parts.
  const GalleryHeaderParts({
    required this.header,
    required this.style,
    required this.albumSwitcher,
    required this.overflow,
  });

  /// The header's state and the preview toggle.
  final AttachSelectionHeaderController header;

  /// The policy's header style.
  final AttachSelectionHeaderStyle style;

  /// The album switcher.
  final Widget albumSwitcher;

  /// The overflow (⋮) button.
  final Widget overflow;
}

/// Builds a Gallery header (the resting one, or the pinned bar's items)
/// from its [GalleryHeaderParts].
typedef GalleryHeaderBuilder =
    Widget Function(BuildContext context, GalleryHeaderParts parts);

/// The stock resting header over the grid, by its style.
///
/// With [AttachSelectionHeaderStyle.showsSelection]:
/// - nothing selected, nothing shows;
/// - with a selection, "N photos selected" (videos, media) rises into place
///   as it fades in, with the overflow button growing in at the end;
/// - from [AttachSelectionHeaderStyle.previewFrom] picks an arrow follows the
///   words and a tap on the header opens the preview; there the header
///   reads "Message preview" behind a back arrow, and a tap goes back;
/// - all of it fades out as the pinned bar fades in at the sheet's top.
///
/// Without it, the album switcher with the overflow button at the end.
class AttachSelectionHeader extends StatefulWidget {
  /// The header of [parts].
  const AttachSelectionHeader({required this.parts, super.key});

  /// What it is built from.
  final GalleryHeaderParts parts;

  /// The header's height.
  static const double height = 44;

  /// The stock builder.
  static Widget builder(BuildContext context, GalleryHeaderParts parts) =>
      AttachSelectionHeader(parts: parts);

  @override
  State<AttachSelectionHeader> createState() => _AttachSelectionHeaderState();
}

class _AttachSelectionHeaderState extends State<AttachSelectionHeader>
    with TickerProviderStateMixin {
  AttachSelectionHeaderController get _header => widget.parts.header;
  AttachSelectionHeaderStyle get _style => widget.parts.style;

  late final AnimationController _$shown;
  late final CurvedAnimation _shown;
  late final AnimationController _$mix;

  // The words last shown, kept while the header fades out.
  AttachSelectionHeaderValue _words = AttachSelectionHeaderValue.initial;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _$shown = AnimationController(
      vsync: this,
      duration: _style.shown.duration,
      value: _header.value.count > 0 ? 1 : 0,
    );
    _shown = CurvedAnimation(parent: _$shown, curve: _style.shown.curve);
    _$mix = AnimationController.unbounded(
      vsync: this,
      value: _header.value.previewing ? 1 : 0,
    );
    _header.addListener(_changed);
    _previewing = _header.value.previewing;
    if (_header.value.count > 0) _words = _header.value;
  }

  // The sheet's grabber fades as the words fade in over its line.
  AttachSheetController? _sheet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sheet = _style.showsSelection
        ? AttachSheetController.maybeOf(context)
        : null;
    if (identical(sheet, _sheet)) return;
    _sheet?.grabberCover = null;
    _sheet = sheet?..grabberCover = _shown;
  }

  @override
  void didUpdateWidget(AttachSelectionHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.parts.header, _header)) {
      oldWidget.parts.header.removeListener(_changed);
      _header.addListener(_changed);
    }
  }

  void _changed() {
    final value = _header.value;
    if (value.count > 0) _words = value;
    final shown = value.count > 0;
    if (shown &&
        _$shown.status != AnimationStatus.forward &&
        _$shown.value < 1) {
      unawaited(_$shown.forward());
    } else if (!shown &&
        _$shown.status != AnimationStatus.reverse &&
        _$shown.value > 0) {
      unawaited(_$shown.reverse());
    }
    if (value.previewing != _previewing) {
      _previewing = value.previewing;
      _swap(to: _previewing ? 1 : 0);
    }
    setState(() {});
  }

  // The header and the preview title swap on the style's spring; the
  // header's toggle waits for it to rest.
  void _swap({required double to}) {
    final spring = _style.previewSwitch;
    if (spring == null) {
      _$mix.value = to;
      _header.switchSettled();
      return;
    }
    _$mix
        .animateWith(SpringSimulation(spring, _$mix.value, to, 0))
        .whenCompleteOrCancel(() {
          if (!mounted) return;
          _$mix.value = to;
          _header.switchSettled();
        });
  }

  void _tap() {
    if (!_style.opensFrom(AttachPreviewEntry.header)) return;
    _header.togglePreview();
  }

  @override
  void dispose() {
    _sheet?.grabberCover = null;
    _header.removeListener(_changed);
    _shown.dispose();
    _$shown.dispose();
    _$mix.dispose();
    super.dispose();
  }

  String _label(AttachStrings strings) {
    final n = math.max(1, _words.count);
    return switch (_words.kinds) {
      AttachSelectionKinds.videos => strings.selectedVideos(n),
      AttachSelectionKinds.media => strings.selectedMedia(n),
      AttachSelectionKinds.photos ||
      AttachSelectionKinds.none => strings.selectedPhotos(n),
    };
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.parts;
    if (!_style.showsSelection) {
      return SizedBox(
        height: AttachSelectionHeader.height,
        child: Row(
          children: [
            Expanded(child: parts.albumSwitcher),
            parts.overflow,
          ],
        ),
      );
    }
    final strings = ChromeStringsScope.attachOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final text = ChromeTypography.of(context).copyWith(
      color: palette.onSurface,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );
    final pinned =
        AttachSheetController.maybeOf(context)?.pinned ??
        const AlwaysStoppedAnimation<double>(0);
    final slide = _style.previewSlide;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final value = _header.value;
    return SizedBox(
      key: const ValueKey('attach-selection-header'),
      height: AttachSelectionHeader.height,
      child: AnimatedBuilder(
        animation: Listenable.merge([_shown, _$mix, pinned]),
        builder: (context, _) {
          final shown = _shown.value;
          final away = 1 - pinned.value;
          final mix = _$mix.value.clamp(0.0, 1.0);
          final live = shown > 0 && away > 0;
          double dx(double d) => rtl ? -d : d;
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !live,
                  child: GestureDetector(
                    key: const ValueKey('attach-selection-header-tap'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _tap,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 23,
                        end: 21 + 44,
                      ),
                      child: Transform.translate(
                        offset: Offset(0, _style.rise * (1 - shown)),
                        child: Opacity(
                          opacity: shown * away,
                          child: Stack(
                            alignment: AlignmentDirectional.centerStart,
                            children: [
                              Transform.translate(
                                offset: Offset(dx(-slide * mix), 0),
                                child: Opacity(
                                  opacity: 1 - mix,
                                  child: Row(
                                    key: const ValueKey(
                                      'attach-selection-header-count',
                                    ),
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _label(strings),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: text,
                                        ),
                                      ),
                                      if (value.canOpenPreview ||
                                          value.previewing)
                                        Padding(
                                          key: const ValueKey(
                                            'attach-selection-header-arrow',
                                          ),
                                          padding:
                                              const EdgeInsetsDirectional.only(
                                                start: 4,
                                                top: 1,
                                              ),
                                          child: Icon(
                                            rtl
                                                ? Icons.chevron_left_rounded
                                                : Icons.chevron_right_rounded,
                                            size: 20,
                                            color: palette.onSurface,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Transform.translate(
                                offset: Offset(dx(slide * (1 - mix)), 0),
                                child: Opacity(
                                  opacity: mix,
                                  child: Row(
                                    key: const ValueKey(
                                      'attach-selection-header-preview',
                                    ),
                                    children: [
                                      Padding(
                                        padding:
                                            const EdgeInsetsDirectional.only(
                                              top: 1,
                                              end: 4,
                                            ),
                                        child: Icon(
                                          rtl
                                              ? Icons.chevron_right_rounded
                                              : Icons.chevron_left_rounded,
                                          size: 20,
                                          color: palette.onSurface,
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(
                                          strings.selectionPreviewTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: text,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // The overflow button grows in beside the header.
              PositionedDirectional(
                end: 12,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !live,
                  child: Opacity(
                    opacity: shown * away,
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * shown,
                      child: Center(child: parts.overflow),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The stock items of the pinned bar: the album switcher, fading out while
/// the preview shows, and the overflow button at the end.
class AttachPinnedItems extends StatelessWidget {
  /// The items of [parts].
  const AttachPinnedItems({required this.parts, super.key});

  /// What they are built from.
  final GalleryHeaderParts parts;

  /// The stock builder.
  static Widget builder(BuildContext context, GalleryHeaderParts parts) =>
      AttachPinnedItems(parts: parts);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ValueListenableBuilder<AttachSelectionHeaderValue>(
          valueListenable: parts.header,
          builder: (context, value, switcher) => IgnorePointer(
            ignoring: value.previewing,
            child: AnimatedOpacity(
              key: const ValueKey('attach-pinned-switcher'),
              opacity: value.previewing ? 0 : 1,
              duration: parts.style.switcherFade.duration,
              curve: parts.style.switcherFade.curve,
              child: switcher,
            ),
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: parts.albumSwitcher,
          ),
        ),
      ),
      parts.overflow,
    ],
  );
}

/// The bar pinned at the sheet's top: the close button (by the style) and
/// the shown page's [items].
class AttachPinnedBar extends StatelessWidget {
  /// The bar over [items].
  const AttachPinnedBar({
    required this.style,
    required this.onClose,
    this.items,
    super.key,
  });

  /// The header style: whether the close button leads, the bar's height.
  final AttachSelectionHeaderStyle style;

  /// A tap on the close button.
  final VoidCallback onClose;

  /// The page's items; null for none.
  final Widget? items;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final strings = ChromeStringsScope.attachOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      height: style.pinnedBarHeight,
      child: Row(
        children: [
          if (style.closeInPinnedBar)
            Semantics(
              button: true,
              label: strings.closeSheet,
              child: GestureDetector(
                key: const ValueKey('attach-pinned-close'),
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: SizedBox(
                  width: 54,
                  height: style.pinnedBarHeight,
                  child: Icon(
                    rtl
                        ? Icons.arrow_forward_rounded
                        : Icons.arrow_back_rounded,
                    color: palette.onSurface,
                  ),
                ),
              ),
            ),
          Expanded(child: items ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}
