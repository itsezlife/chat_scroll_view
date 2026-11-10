import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_drag.dart';
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
/// a pointer.
///
/// The sheet itself ([StickerPackSheet], [EmojiPackSheet]) reads the
/// arrangement from the `PanelArrangementScope` this puts above it: a grabber
/// on touch, and a tall sheet that opens part-way and rises with its grid
/// (`PackSheetFrame`); a close button and a bounded box under a pointer.
///
/// On touch one drag owner moves the sheet: a pull down past the grid's top
/// or on the header band lowers it, and closes it past [dismissDistance] or
/// on a flick of [dismissVelocity]; a push up undoes the pull before the
/// card rises with the grid. The box under a pointer is never dragged.
///
/// [StickerPackSheet]: package:panel_pages/src/pack_sheet/sticker_pack_sheet.dart
/// [EmojiPackSheet]: package:panel_pages/src/pack_sheet/emoji_pack_sheet.dart
abstract final class PackSheet {
  /// The `RouteSettings.name` of the route [show] pushes, in either
  /// arrangement.
  ///
  /// A host that pauses its animations under modal routes tells the sheet
  /// apart by it: the sheet plays its own content and the preview opened
  /// from it. Only what is under the sheet pauses (the sheet's cells are on
  /// layer 7 and its preview above every layer), and everything pauses while
  /// the sheet opens or closes.
  static const String routeName = 'pack_sheet';

  /// The dim behind the bottom sheet: `BottomSheet`'s backDrawable alpha
  /// `0x33` of black.
  static const Color touchBarrier = Color(0x33000000);

  /// The dim behind the box: `#0000007f`.
  static const Color pointerBarrier = Color(0x7F000000);

  /// How long the bottom sheet takes to open: `BottomSheet.startOpenAnimation`
  /// runs 400 ms on `EASE_OUT_QUINT` after a 20 ms delay.
  static const Duration openDuration = Duration(milliseconds: 420);

  /// The delay inside [openDuration] before the sheet moves.
  static const Duration openDelay = Duration(milliseconds: 20);

  /// How long the bottom sheet takes to close: `dismissInternal` runs 250 ms
  /// on `EASE_OUT`.
  static const Duration closeDuration = Duration(milliseconds: 250);

  /// How far a drag must pull the sheet down to dismiss it: 0.8 cm, at the
  /// 160 dpi of one logical pixel.
  static const double dismissDistance = 0.8 / 2.54 * 160;

  /// The fling that dismisses whatever the distance: 3500 physical pixels per
  /// second.
  static const double dismissVelocity = 3500;

  /// The width of the box under a pointer.
  static const double boxWidth = 364;

  /// How long the box takes to fade in or out.
  static const Duration boxFade = Duration(milliseconds: 200);

  /// Shows the sheet [builder] builds over [context]'s navigator, arranged for
  /// [arrangement]. Completes when the sheet has gone.
  ///
  /// Under a pointer the box is the first box of a `ChromeBoxLayer`: a box
  /// the sheet's host shows from it (`ChromeBoxLayer.of(sheetContext)`), such
  /// as a confirmation, takes the box's place at once on the same layer, and
  /// the box comes back when that one closes.
  static Future<void> show(
    BuildContext context, {
    required PanelArrangement arrangement,
    required WidgetBuilder builder,
  }) {
    final speed = ChromeMotionScope.maybeOf(context)?.speed;
    return switch (arrangement) {
      PanelArrangement.touch => Navigator.of(
        context,
      ).push(_BottomSheetRoute(builder: builder, speed: speed)),
      PanelArrangement.pointer => _showBox(
        context,
        builder: builder,
        speed: speed,
      ),
    };
  }
}

/// The root of both routes' pages: the arrangement, the text style and room
/// for the keyboard.
///
/// A popup route has no `Material` above it, and the context that opens the
/// sheet often has none either (a host's screen above its scaffold), so an
/// inherited style is the framework's debug one; the sheet's text is the
/// chrome face ([ChromeTypography]) in the chrome palette's `onSurface`. The
/// routes do not take focus, so a raised keyboard stays up: the page lays out
/// above it.
class _SheetRoot extends StatelessWidget {
  const _SheetRoot({required this.arrangement, required this.child});

  final PanelArrangement arrangement;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    return PanelArrangementScope(
      arrangement: arrangement,
      child: DefaultTextStyle(
        style: ChromeTypography.of(context).copyWith(color: palette.onSurface),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: child,
        ),
      ),
    );
  }
}

// --- Bottom sheet -----------------------------------------------------------

final class _BottomSheetRoute extends PopupRoute<void> {
  _BottomSheetRoute({required this.builder, this.speed})
    : super(
        requestFocus: false,
        settings: const RouteSettings(name: PackSheet.routeName),
      );

  final WidgetBuilder builder;
  final ChromeMotionSpeed? speed;

  @override
  Color get barrierColor => PackSheet.touchBarrier;

  // A tap above the content dismisses.
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
  ) => _SheetRoot(
    arrangement: PanelArrangement.touch,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: _SheetDrag(child: Builder(builder: builder)),
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

/// The bottom sheet's drag owner ([PackSheetDrag]): translates the sheet
/// under a pull from the grid or the header, closes it past
/// [PackSheet.dismissDistance] or on a flick of [PackSheet.dismissVelocity],
/// and otherwise springs it back in `250 * (pull / distance)` ms on an ease
/// out. Its sink reaches the sheet's body through [PackSheetDragScope].
class _SheetDrag extends StatefulWidget {
  const _SheetDrag({required this.child});

  final Widget child;

  @override
  State<_SheetDrag> createState() => _SheetDragState();
}

class _SheetDragState extends State<_SheetDrag>
    with SingleTickerProviderStateMixin {
  final _drag = PackSheetDrag(
    dismissDistance: PackSheet.dismissDistance,
    dismissVelocity: PackSheet.dismissVelocity,
  );
  late final AnimationController _back = AnimationController(vsync: this)
    ..addListener(() => _moveTo(_back.value));
  final _translation = ValueNotifier<double>(0);
  var _dismissed = false;

  late final _sink = CatalogOverscrollSink(
    onStart: _back.stop,
    onDelta: (pixels) {
      if (_dismissed) return 0;
      final taken = _drag.take(pixels);
      _translation.value = _drag.translation;
      return taken;
    },
    onEnd: _release,
  );

  void _moveTo(double translation) {
    _drag.translation = translation;
    _translation.value = _drag.translation;
  }

  bool _release(double velocity) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    switch (_drag.release(velocity * ratio)) {
      case PackSheetRelease.rest:
        return false;
      case PackSheetRelease.dismiss:
        _dismissed = true;
        Navigator.of(context).pop();
      case PackSheetRelease.springBack:
        final back =
            PackSheet.closeDuration *
            (_drag.translation / PackSheet.dismissDistance);
        final speed = ChromeMotionScope.maybeOf(context)?.speed;
        _back
          ..value = _drag.translation
          ..animateTo(
            0,
            duration: speed?.scale(back) ?? back,
            curve: Curves.easeOut,
          );
    }
    return true;
  }

  @override
  void dispose() {
    _back.dispose();
    _translation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PackSheetDragScope(
    sink: _sink,
    child: ValueListenableBuilder(
      valueListenable: _translation,
      child: widget.child,
      builder: (context, translation, child) =>
          Transform.translate(offset: Offset(0, translation), child: child),
    ),
  );
}

// --- Box --------------------------------------------------------------------

// The box opens a box layer: a confirmation shown from the box takes its
// place on the same layer, and the box comes back when it closes.
Future<void> _showBox(
  BuildContext context, {
  required WidgetBuilder builder,
  required ChromeMotionSpeed? speed,
}) => ChromeBoxLayer.open<void>(
  context,
  barrierColor: PackSheet.pointerBarrier,
  transitionDuration: speed?.scale(PackSheet.boxFade) ?? PackSheet.boxFade,
  requestFocus: false,
  settings: const RouteSettings(name: PackSheet.routeName),
  builder: (context) => _SheetRoot(
    arrangement: PanelArrangement.pointer,
    child: SizedBox(
      width: PackSheet.boxWidth,
      child: Builder(builder: builder),
    ),
  ),
);
