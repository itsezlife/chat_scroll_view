import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:attach_sheet/src/sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:mpx_ui/mpx_ui.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

/// The Gallery grid's fast scroll: the policy's thumb over the grid and,
/// beside it, the month the items at the top of the view were taken in.
///
/// It shows while the sheet is at its top (always outside a sheet) and
/// the album holds the policy's fewest items or more.
@internal
class GalleryFastScroll extends StatefulWidget {
  /// The fast scroll over [child], the grid on [controller] that [lookup]
  /// answers for.
  const GalleryFastScroll({
    required this.controller,
    required this.lookup,
    required this.policy,
    required this.child,
    super.key,
  });

  /// The grid's scroll controller.
  final ScrollController controller;

  /// What the grid holds at a scroll offset.
  final LibraryGridLookup lookup;

  /// The sheet's platform values.
  final AttachSheetPolicy policy;

  /// The grid.
  final Widget child;

  @override
  State<GalleryFastScroll> createState() => _GalleryFastScrollState();
}

class _GalleryFastScrollState extends State<GalleryFastScroll> {
  AttachSheetController? _sheet;
  bool _atTop = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sheet = AttachSheetController.maybeOf(context);
    if (identical(sheet, _sheet)) return;
    _sheet?.top.removeListener(_onTop);
    _sheet = sheet?..top.addListener(_onTop);
    _atTop = sheet?.isExpanded ?? true;
  }

  @override
  void dispose() {
    _sheet?.top.removeListener(_onTop);
    super.dispose();
  }

  // The top moves every frame of the sheet's motion; only reaching or
  // leaving the top rebuilds.
  void _onTop() {
    final atTop = _sheet?.isExpanded ?? true;
    if (atTop != _atTop) setState(() => _atTop = atTop);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.attachOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final policy = widget.policy;
    final lookup = widget.lookup;
    final fast = policy.libraryFastScroll;
    return ListenableBuilder(
      listenable: lookup,
      builder: (context, child) => FastScrollbar(
        controller: widget.controller,
        policy: fast,
        style: _style(fast, palette),
        labelAt: (offset) => switch (lookup.assetAt(offset)?.created) {
          final date? => strings.libraryMonth(date.toLocal()),
          null => null,
        },
        labelsChanged: lookup,
        enabled: _atTop && lookup.count >= policy.libraryFastScrollMinCount,
        // The track ends where the grid's visible content ends: above the
        // floating bars and the safe area, the grid's own bottom padding.
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: child!,
      ),
      child: widget.child,
    );
  }

  // The tab thumb and its label share a fill a touch lighter than the
  // sheet; the line thumb is the system's scroll indicator grey, its label
  // on the raised surface. Both stand on the top panel's glass.
  static FastScrollbarStyle _style(
    FastScrollbarPolicy policy,
    ChromePalette palette,
  ) {
    const white = Color(0xFFFFFFFF);
    final light = palette.brightness == Brightness.light;
    return switch (policy.thumb) {
      FastScrollThumb$Tab() => FastScrollbarStyle(
        thumbColor: Color.lerp(palette.surfaceRaised, white, 0.1)!,
        thumbIconColor: palette.onSurface,
        labelColor: Color.lerp(palette.surfaceRaised, white, 0.1)!,
        labelTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: palette.onSurface,
        ),
        surfaceBuilder: _glass,
      ),
      FastScrollThumb$Line() => FastScrollbarStyle(
        thumbColor: light ? const Color(0x4D000000) : const Color(0x80FFFFFF),
        thumbIconColor: palette.onSurface,
        labelColor: palette.surfaceRaised,
        labelTextStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: palette.onSurface,
        ),
        surfaceBuilder: _glass,
      ),
    };
  }

  static Widget _glass(BuildContext context, ShapeBorder shape, Widget child) =>
      GlassSurface(
        material: GlassMaterial.topPanel,
        cornerRadius: switch (shape) {
          RoundedRectangleBorder(borderRadius: BorderRadius(:final topLeft)) =>
            topLeft.x,
          // A circle: a radius past half the side rounds it whole.
          _ => 1000,
        },
        child: child,
      );
}
