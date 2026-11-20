import 'package:chrome_foundation/src/motion/chrome_motion_scope.dart';
import 'package:chrome_foundation/src/motion/chrome_motion_speed.dart';
import 'package:chrome_foundation/src/sheet/chrome_sheet_pull.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_scope.dart';
import 'package:chrome_foundation/src/theme/chrome_typography.dart';
import 'package:flutter/widgets.dart';

/// How a [ChromeSheetRoute] opens and closes.
@immutable
sealed class ChromeSheetOpening {
  const ChromeSheetOpening();

  /// The route slides the sheet up from the bottom edge over [open] (after
  /// [delay] inside it, on [openCurve]) and back down over [close] (on
  /// [closeCurve]), and fades its barrier in and out with it.
  const factory ChromeSheetOpening.slide({
    required Duration open,
    required Duration close,
    Duration delay,
    Curve openCurve,
    Curve closeCurve,
  }) = ChromeSheetOpening$Slide;

  /// The content runs its own open and close (springs, a morph out of the
  /// control that opened it, a scrim of its own): the route shows and goes
  /// at once, and the content pops it when its close has run.
  const factory ChromeSheetOpening.byContent() = ChromeSheetOpening$ByContent;
}

/// See [ChromeSheetOpening.slide].
final class ChromeSheetOpening$Slide extends ChromeSheetOpening {
  /// See [ChromeSheetOpening.slide].
  const ChromeSheetOpening$Slide({
    required this.open,
    required this.close,
    this.delay = Duration.zero,
    this.openCurve = Curves.easeOutQuint,
    this.closeCurve = Curves.easeOut,
  });

  /// How long the open takes, [delay] included.
  final Duration open;

  /// How long the close takes.
  final Duration close;

  /// The wait inside [open] before the sheet moves.
  final Duration delay;

  /// The open's curve, after the delay.
  final Curve openCurve;

  /// The close's curve.
  final Curve closeCurve;
}

/// See [ChromeSheetOpening.byContent].
final class ChromeSheetOpening$ByContent extends ChromeSheetOpening {
  /// See [ChromeSheetOpening.byContent].
  const ChromeSheetOpening$ByContent();
}

/// What a host lays over a sheet's whole layer: [child] is the layer with
/// its open and close motion; the builder returns it with the host's own
/// layer on top, which neither moves nor fades with it.
typedef ChromeSheetLayerBuilder =
    Widget Function(BuildContext context, Widget child);

/// The root of a sheet's or a box's page: the chrome text style, and room
/// for the keyboard.
///
/// A popup route has no `Material` above it, and the context that opens it
/// often has none either (a host's screen above its scaffold), so the
/// inherited text style is the framework's debug one (underlined); the
/// root's is the chrome face ([ChromeTypography]) in the chrome palette's
/// `onSurface`. With [avoidsKeyboard] the page lays out above a raised
/// keyboard; a page that places itself around the keyboard turns it off.
class ChromeSheetRoot extends StatelessWidget {
  /// A root above [child].
  const ChromeSheetRoot({
    required this.child,
    this.avoidsKeyboard = true,
    super.key,
  });

  /// Whether the page is padded up by the keyboard's height.
  final bool avoidsKeyboard;

  /// The page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    return DefaultTextStyle(
      style: ChromeTypography.of(context).copyWith(color: palette.onSurface),
      child: avoidsKeyboard
          ? Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: child,
            )
          : child,
    );
  }
}

/// The chrome's modal **bottom sheet** route: the touch counterpart of
/// `ChromeBoxLayer`.
///
/// Its page is a [ChromeSheetRoot] (the chrome text style, room for the
/// keyboard) around what [builder] builds; it opens and closes by its
/// [opening]; with a [drag] spec the content's drags pull it down through
/// [ChromeSheetDrag] and close it by that rule. It takes no focus, so a
/// raised keyboard stays up.
///
/// A sheet that needs more of its route (a notifier the route owns) extends
/// it.
base class ChromeSheetRoute<T> extends PopupRoute<T> {
  /// A sheet [builder] builds, over [barrierColor].
  ChromeSheetRoute({
    required this.builder,
    required this.opening,
    this.barrierColor,
    this.barrierDismissible = true,
    this.drag,
    this.avoidsKeyboard = true,
    this.layer,
    this.speed,
    super.settings,
  }) : super(requestFocus: false);

  /// Pushes a sheet over [context]'s navigator at the motion speed of the
  /// nearest `ChromeMotionScope`; completes when the sheet has gone.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    required ChromeSheetOpening opening,
    Color? barrierColor,
    bool barrierDismissible = true,
    ChromeSheetDragSpec? drag,
    bool avoidsKeyboard = true,
    ChromeSheetLayerBuilder? layer,
    RouteSettings? settings,
  }) => Navigator.of(context).push(
    ChromeSheetRoute<T>(
      builder: builder,
      opening: opening,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      drag: drag,
      avoidsKeyboard: avoidsKeyboard,
      layer: layer,
      speed: ChromeMotionScope.maybeOf(context)?.speed,
      settings: settings,
    ),
  );

  /// The sheet.
  final WidgetBuilder builder;

  /// How it opens and closes.
  final ChromeSheetOpening opening;

  /// How a pull down closes it; null when no drag moves it (or the content
  /// moves itself).
  final ChromeSheetDragSpec? drag;

  /// Whether the page lays out above a raised keyboard.
  final bool avoidsKeyboard;

  /// The host's layer over the sheet's.
  final ChromeSheetLayerBuilder? layer;

  /// The motion speed the open and close durations scale by.
  final ChromeMotionSpeed? speed;

  @override
  final Color? barrierColor;

  @override
  final bool barrierDismissible;

  @override
  String? get barrierLabel => null;

  Duration _scaled(Duration duration) => speed?.scale(duration) ?? duration;

  @override
  Duration get transitionDuration => switch (opening) {
    ChromeSheetOpening$Slide(:final open) => _scaled(open),
    ChromeSheetOpening$ByContent() => Duration.zero,
  };

  @override
  Duration get reverseTransitionDuration => switch (opening) {
    ChromeSheetOpening$Slide(:final close) => _scaled(close),
    ChromeSheetOpening$ByContent() => Duration.zero,
  };

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    Widget sheet = Builder(builder: builder);
    if (drag case final spec?)
      sheet = ChromeSheetDrag(spec: spec, child: sheet);
    return ChromeSheetRoot(
      avoidsKeyboard: avoidsKeyboard,
      child: switch (opening) {
        ChromeSheetOpening$Slide() => Align(
          alignment: Alignment.bottomCenter,
          child: sheet,
        ),
        ChromeSheetOpening$ByContent() => sheet,
      },
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final sheet = switch (opening) {
      final ChromeSheetOpening$Slide slide => _slide(slide, animation, child),
      ChromeSheetOpening$ByContent() => child,
    };
    return switch (layer) {
      final layer? => layer(context, sheet),
      null => sheet,
    };
  }

  static Widget _slide(
    ChromeSheetOpening$Slide slide,
    Animation<double> animation,
    Widget child,
  ) {
    final open = slide.open.inMicroseconds;
    final delay = open == 0 ? 0.0 : slide.delay.inMicroseconds / open;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(delay, 1, curve: slide.openCurve),
      reverseCurve: slide.closeCurve,
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

/// A bottom sheet's drag owner ([ChromeSheetPull]): translates the sheet
/// under a pull from its content, closes it (pops its route) by [spec], and
/// otherwise springs it back. Its sink reaches the content through
/// [maybeOf].
class ChromeSheetDrag extends StatefulWidget {
  /// An owner moving [child] by [spec].
  const ChromeSheetDrag({required this.spec, required this.child, super.key});

  /// The dismiss rule.
  final ChromeSheetDragSpec spec;

  /// The sheet.
  final Widget child;

  /// The sink of the nearest owner, or null where no drag moves the sheet.
  static ChromeSheetDragSink? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DragScope>()?.sink;

  @override
  State<ChromeSheetDrag> createState() => _ChromeSheetDragState();
}

class _ChromeSheetDragState extends State<ChromeSheetDrag>
    with SingleTickerProviderStateMixin
    implements ChromeSheetDragSink {
  late final ChromeSheetPull _pull = ChromeSheetPull(widget.spec);
  late final AnimationController _back;
  final _translation = ValueNotifier<double>(0);
  var _dismissed = false;

  @override
  void initState() {
    super.initState();
    _back = AnimationController(vsync: this)
      ..addListener(() => _moveTo(_back.value));
  }

  void _moveTo(double translation) {
    _pull.translation = translation;
    _translation.value = _pull.translation;
  }

  @override
  void start() => _back.stop();

  @override
  double take(double pixels) {
    if (_dismissed) return 0;
    final taken = _pull.take(pixels);
    _translation.value = _pull.translation;
    return taken;
  }

  @override
  bool release(double velocity) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    switch (_pull.release(velocity * ratio)) {
      case ChromeSheetRelease.rest:
        return false;
      case ChromeSheetRelease.dismiss:
        _dismissed = true;
        Navigator.of(context).pop();
      case ChromeSheetRelease.springBack:
        final back =
            widget.spec.springBack *
            (_pull.translation / widget.spec.dismissDistance);
        final speed = ChromeMotionScope.maybeOf(context)?.speed;
        _back
          ..value = _pull.translation
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
  Widget build(BuildContext context) => _DragScope(
    sink: this,
    child: ValueListenableBuilder(
      valueListenable: _translation,
      child: widget.child,
      builder: (context, translation, child) =>
          Transform.translate(offset: Offset(0, translation), child: child),
    ),
  );
}

class _DragScope extends InheritedWidget {
  const _DragScope({required this.sink, required super.child});

  final ChromeSheetDragSink sink;

  @override
  bool updateShouldNotify(_DragScope oldWidget) =>
      !identical(sink, oldWidget.sink);
}
