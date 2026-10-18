import 'dart:math' as math;

import 'package:chat_composer/src/menu/selection_menu_metrics.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/widgets.dart';

/// Where the selection menu goes for one selection: which side, how much room,
/// and the region it is laid out in.
@immutable
final class SelectionMenuPlacement {
  /// A placement with every part given.
  const SelectionMenuPlacement({
    required this.fitsAbove,
    required this.maxHeight,
    required this.maxWidth,
    required this.padding,
    required this.localAdjustment,
    required this.anchorAbove,
    required this.anchorBelow,
  });

  /// Whether the menu opens above the selection.
  final bool fitsAbove;

  /// The tallest the card may be on the chosen side.
  final double maxHeight;

  /// The widest the card may be.
  final double maxWidth;

  /// The region the card is laid out in, inside the screen.
  final EdgeInsets padding;

  /// The offset from screen coordinates to the region's.
  final Offset localAdjustment;

  /// Where the card's bottom edge goes when it is above, in screen
  /// coordinates.
  final Offset anchorAbove;

  /// Where the card's top edge goes when it is below, in screen coordinates.
  final Offset anchorBelow;
}

/// Places the menu from the selection's [anchors], the safe area and the
/// keyboard.
///
/// It prefers the side above the selection. It goes below when the room above
/// is under [maxHeight] and the room below is not, and to whichever side has
/// more when neither is enough; the room it takes is capped to that side. When
/// part of the selection has scrolled off screen the anchors are pulled into
/// the visible band, so the menu stays by the end that can be seen.
///
/// [safe] is the larger of the platform's padding and view padding; the
/// keyboard's inset replaces its bottom while the keyboard is open, since it
/// covers the navigation bar.
SelectionMenuPlacement computeSelectionMenuPlacement({
  required Size screen,
  required EdgeInsets safe,
  required double keyboardInset,
  required TextSelectionToolbarAnchors anchors,
  double maxHeight = SelectionMenuMetrics.maxHeight,
  double maxWidth = SelectionMenuMetrics.rowMaxWidth,
}) {
  const margin = SelectionMenuMetrics.regionMargin;
  const gapAbove = SelectionMenuMetrics.gapAbove;
  const gapBelow = SelectionMenuMetrics.gapBelow;

  final bottomInset =
      (keyboardInset > 0 ? keyboardInset : safe.bottom) + margin;
  final viewTop = safe.top + margin;
  final viewBottom = screen.height - bottomInset;

  var primary = anchors.primaryAnchor;
  var secondary = anchors.secondaryAnchor ?? primary;
  primary = _preferVisible(primary, secondary, viewTop, viewBottom);
  secondary = _preferVisible(secondary, primary, viewTop, viewBottom);

  final spaceAbove = math.max<double>(
    0,
    primary.dy - gapAbove - safe.top - margin,
  );
  final spaceBelow = math.max<double>(
    0,
    screen.height - bottomInset - secondary.dy - gapBelow,
  );

  var above = true;
  if (spaceAbove >= maxHeight) {
    above = true;
  } else if (spaceBelow >= maxHeight) {
    above = false;
  } else {
    above = spaceAbove >= spaceBelow;
  }
  final chosen = above ? spaceAbove : spaceBelow;
  final other = above ? spaceBelow : spaceAbove;
  if (chosen < SelectionMenuMetrics.minUsableHeight && other > chosen) {
    above = !above;
  }

  return SelectionMenuPlacement(
    fitsAbove: above,
    maxHeight: math.min(maxHeight, above ? spaceAbove : spaceBelow),
    maxWidth: math.min(
      maxWidth,
      math.max<double>(0, screen.width - margin * 2),
    ),
    padding: EdgeInsets.fromLTRB(
      margin,
      safe.top + margin,
      margin,
      bottomInset,
    ),
    localAdjustment: Offset(margin, safe.top + margin),
    anchorAbove: primary - const Offset(0, gapAbove),
    anchorBelow: secondary + const Offset(0, gapBelow),
  );
}

// Keeps [candidate] when it is on screen, else [other] when that is, else the
// candidate clamped into the band.
Offset _preferVisible(
  Offset candidate,
  Offset other,
  double viewTop,
  double viewBottom,
) {
  bool inView(Offset anchor) => anchor.dy >= viewTop && anchor.dy <= viewBottom;
  if (inView(candidate)) return candidate;
  if (inView(other)) return other;
  return Offset(candidate.dx, candidate.dy.clamp(viewTop, viewBottom));
}

/// The anchors of the selection in [editable], at its endpoints.
///
/// Not [ExtendedEditableTextState.contextMenuAnchors], which prefers the last
/// secondary-tap position: after a right click the menu would stay where the
/// click was while the selection scrolls away from it.
TextSelectionToolbarAnchors selectionMenuAnchors(
  ExtendedEditableTextState editable,
) {
  final selection = editable.textEditingValue.selection;
  if (!selection.isValid) return editable.contextMenuAnchors;
  final render = editable.renderEditable;
  final points = render.getEndpointsForSelection(selection);
  if (points.isEmpty) return editable.contextMenuAnchors;
  final heights = editable.getGlyphHeights();
  return TextSelectionToolbarAnchors.fromSelection(
    renderBox: render,
    startGlyphHeight: heights.startGlyphHeight,
    endGlyphHeight: heights.endGlyphHeight,
    selectionEndpoints: points,
  );
}

/// Lays the card out in the [SelectionMenuPlacement]'s region.
///
/// Under the editable's toolbar follower the menu's local space is the
/// screen's, so the anchors are converted by the region's offset alone;
/// `globalToLocal` would apply the follower's transform twice.
class SelectionMenuPositioned extends StatelessWidget {
  /// Lays [child] out for [placement].
  const SelectionMenuPositioned({
    required this.placement,
    required this.child,
    this.referenceWidth,
    super.key,
  });

  /// Where the card goes.
  final SelectionMenuPlacement placement;

  /// The width the card is centred as before it hugs an edge of it; see
  /// [SelectionMenuLayoutDelegate].
  final double? referenceWidth;

  /// The card.
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: placement.padding,
    child: CustomSingleChildLayout(
      delegate: SelectionMenuLayoutDelegate(
        anchorAbove: placement.anchorAbove - placement.localAdjustment,
        anchorBelow: placement.anchorBelow - placement.localAdjustment,
        fitsAbove: placement.fitsAbove,
        referenceWidth: referenceWidth,
        textDirection: Directionality.of(context),
      ),
      child: child,
    ),
  );
}

/// Places the card by one anchor, keeping one horizontal edge still while the
/// card changes width between pages.
///
/// The card is centred on the anchor as if it were [referenceWidth] wide (the
/// main row's), and a narrower page hugs that width's trailing edge, or its
/// leading edge in right-to-left: opening the page then keeps one edge where it
/// was, instead of walking the card sideways. Above the selection the card's
/// bottom edge is at the anchor, so a page that grows grows upwards.
@immutable
class SelectionMenuLayoutDelegate extends SingleChildLayoutDelegate {
  /// A delegate for the anchors, in the region's coordinates.
  const SelectionMenuLayoutDelegate({
    required this.anchorAbove,
    required this.anchorBelow,
    required this.fitsAbove,
    this.referenceWidth,
    this.textDirection = TextDirection.ltr,
  });

  /// The anchor used when [fitsAbove].
  final Offset anchorAbove;

  /// The anchor used when not [fitsAbove].
  final Offset anchorBelow;

  /// Whether the card is above the selection.
  final bool fitsAbove;

  /// The width the card is centred as.
  final double? referenceWidth;

  /// Which edge is the trailing one.
  final TextDirection textDirection;

  // The card shrink-wraps its page: tight constraints would stretch it over
  // the whole region and park it against the region's top edge.
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final anchor = fitsAbove ? anchorAbove : anchorBelow;
    final reference = math.min(
      math.max(referenceWidth ?? childSize.width, childSize.width),
      size.width,
    );
    final slack = math.max<double>(0, size.width - reference);
    final referenceX = (anchor.dx - reference / 2).clamp(0, slack).toDouble();
    final x = switch (textDirection) {
      TextDirection.ltr => referenceX + reference - childSize.width,
      TextDirection.rtl => referenceX,
    };
    return Offset(
      x,
      fitsAbove ? math.max(0, anchor.dy - childSize.height) : anchor.dy,
    );
  }

  @override
  bool shouldRelayout(SelectionMenuLayoutDelegate oldDelegate) =>
      anchorAbove != oldDelegate.anchorAbove ||
      anchorBelow != oldDelegate.anchorBelow ||
      fitsAbove != oldDelegate.fitsAbove ||
      referenceWidth != oldDelegate.referenceWidth ||
      textDirection != oldDelegate.textDirection;
}
