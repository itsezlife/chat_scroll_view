import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/panel_shell.dart';

/// The link of the pack [id] to share or copy, or null for a pack that has
/// none. A host without links (no backend yet) passes no builder at all, and
/// the sheet shows no menu.
typedef PackLinkBuilder = Uri? Function(PackId id);

/// Where a pack sheet's menu gets a pack's link and what Share and Copy Link
/// do with it: both are the host's (a share sheet, the clipboard and its
/// confirmation), so the sheet stays effect-free.
@immutable
final class PackSheetLinks {
  /// Links built by [linkOf], shared by [onShare] and copied by [onCopy].
  const PackSheetLinks({
    required this.linkOf,
    required this.onShare,
    required this.onCopy,
  });

  /// The pack's link, or null: no link, no menu.
  final PackLinkBuilder linkOf;

  /// The user chose Share for the link.
  final ValueChanged<Uri> onShare;

  /// The user chose Copy Link for the link; the host writes the clipboard and
  /// confirms it (`PackSheetStrings.linkCopied`).
  final ValueChanged<Uri> onCopy;
}

/// One item of a pack sheet's grid, with the pack it is shown in.
typedef PackSheetItem = ({ContentDescriptor item, Pack pack});

/// Shows a pack sheet: a modal bottom sheet on touch and a centred box under
/// a pointer, as the reference clients do (the mobile client's
/// `StickersAlert` / `EmojiPacksAlert` bottom sheets, the desktop client's
/// `StickerSetBox`).
///
/// The sheet itself ([StickerPackSheet], [EmojiPackSheet]) reads the
/// arrangement from the `PanelArrangementScope` this puts above it: a grabber
/// and a part-way height on touch, a close button and a bounded box under a
/// pointer.
///
/// [StickerPackSheet]: package:panel_pages/src/pack_sheet/sticker_pack_sheet.dart
/// [EmojiPackSheet]: package:panel_pages/src/pack_sheet/emoji_pack_sheet.dart
abstract final class PackSheet {
  /// The dim behind the bottom sheet: `BottomSheet`'s backDrawable alpha
  /// `0x33` of black.
  static const Color touchBarrier = Color(0x33000000);

  /// The dim behind the box: the desktop client's `layerBg` (`#0000007f`).
  static const Color pointerBarrier = Color(0x7F000000);

  /// How long the bottom sheet takes to open: `BottomSheet.startOpenAnimation`
  /// runs 400 ms on `EASE_OUT_QUINT` after a 20 ms delay.
  static const Duration openDuration = Duration(milliseconds: 420);

  /// The delay inside [openDuration] before the sheet moves.
  static const Duration openDelay = Duration(milliseconds: 20);

  /// How long the bottom sheet takes to close: `dismissInternal` runs 250 ms
  /// on `EASE_OUT`.
  static const Duration closeDuration = Duration(milliseconds: 250);

  /// How far a drag must pull the sheet down to dismiss it: `BottomSheet`'s
  /// `0.8 cm` (`getPixelsInCM(0.8f)`), at the 160 dpi of one logical pixel.
  static const double dismissDistance = 0.8 / 2.54 * 160;

  /// The fling that dismisses whatever the distance: 3500 physical pixels per
  /// second (`velocityY >= 3500`).
  static const double dismissVelocity = 3500;

  /// The width of the box under a pointer: the desktop client's
  /// `boxWideWidth`.
  static const double boxWidth = 364;

  /// Shows the sheet [builder] builds over [context]'s navigator, arranged for
  /// [arrangement]. Completes when the sheet has gone.
  static Future<void> show(
    BuildContext context, {
    required PanelArrangement arrangement,
    required WidgetBuilder builder,
  }) => Navigator.of(context).push(switch (arrangement) {
    PanelArrangement.touch => _BottomSheetRoute(
      builder: builder,
      speed: ChromeMotionScope.maybeOf(context)?.speed,
    ),
    PanelArrangement.pointer => _BoxRoute(
      builder: builder,
      speed: ChromeMotionScope.maybeOf(context)?.speed,
    ),
  });
}

// --- Bottom sheet -----------------------------------------------------------

final class _BottomSheetRoute extends PopupRoute<void> {
  _BottomSheetRoute({required this.builder, this.speed});

  final WidgetBuilder builder;
  final ChromeMotionSpeed? speed;

  @override
  Color get barrierColor => PackSheet.touchBarrier;

  // A tap above the content dismisses (`StickersAlert` `onTouchEvent`).
  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration =>
      speed?.scale(PackSheet.openDuration) ?? PackSheet.openDuration;

  @override
  Duration get reverseTransitionDuration =>
      speed?.scale(PackSheet.closeDuration) ?? PackSheet.closeDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => PanelArrangementScope(
    arrangement: PanelArrangement.touch,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: _DragToDismiss(
        route: this,
        child: Builder(builder: builder),
      ),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final delay =
        PackSheet.openDelay.inMicroseconds /
        PackSheet.openDuration.inMicroseconds;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(delay, 1, curve: Curves.easeOutQuint),
      reverseCurve: Curves.easeOut,
    );
    return AnimatedBuilder(
      animation: curved,
      child: child,
      builder: (context, child) => FractionalTranslation(
        translation: Offset(0, 1 - curved.value),
        child: child,
      ),
    );
  }
}

/// Pulls the sheet down under a vertical drag that its scrolling grid does
/// not take, and dismisses it past [PackSheet.dismissDistance] or on a fast
/// fling; otherwise it springs back in `250 * (offset / distance)` ms
/// (`BottomSheet.checkDismiss`).
class _DragToDismiss extends StatefulWidget {
  const _DragToDismiss({required this.route, required this.child});

  final _BottomSheetRoute route;
  final Widget child;

  @override
  State<_DragToDismiss> createState() => _DragToDismissState();
}

class _DragToDismissState extends State<_DragToDismiss>
    with SingleTickerProviderStateMixin {
  late final _back = AnimationController(vsync: this);
  var _offset = 0.0;

  @override
  void initState() {
    super.initState();
    _back.addListener(() => setState(() => _offset = _back.value));
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails details) {
    _back.stop();
    setState(() => _offset = math.max(0, _offset + details.delta.dy));
  }

  void _end(DragEndDetails details) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final fling = details.velocity.pixelsPerSecond.dy * ratio;
    if (_offset > PackSheet.dismissDistance ||
        fling >= PackSheet.dismissVelocity) {
      Navigator.of(context).pop();
      return;
    }
    final back =
        PackSheet.closeDuration * (_offset / PackSheet.dismissDistance);
    final speed = ChromeMotionScope.maybeOf(context)?.speed;
    _back
      ..value = _offset
      ..animateTo(
        0,
        duration: speed?.scale(back) ?? back,
        curve: Curves.easeOut,
      );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onVerticalDragUpdate: _update,
    onVerticalDragEnd: _end,
    child: Transform.translate(offset: Offset(0, _offset), child: widget.child),
  );
}

// --- Box --------------------------------------------------------------------

final class _BoxRoute extends PopupRoute<void> {
  _BoxRoute({required this.builder, this.speed});

  final WidgetBuilder builder;
  final ChromeMotionSpeed? speed;

  static const Duration _fade = Duration(milliseconds: 200);

  @override
  Color get barrierColor => PackSheet.pointerBarrier;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => speed?.scale(_fade) ?? _fade;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => PanelArrangementScope(
    arrangement: PanelArrangement.pointer,
    child: Center(
      child: SizedBox(
        width: PackSheet.boxWidth,
        child: Builder(builder: builder),
      ),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}
