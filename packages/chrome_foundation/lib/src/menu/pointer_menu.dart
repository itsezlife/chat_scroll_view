import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chrome_foundation/src/menu/pointer_menu_aim.dart';
import 'package:chrome_foundation/src/menu/pointer_menu_entry.dart';
import 'package:chrome_foundation/src/menu/pointer_menu_metrics.dart';
import 'package:chrome_foundation/src/menu/pointer_menu_placement.dart';
import 'package:chrome_foundation/src/menu/pointer_menu_reveal.dart';
import 'package:chrome_foundation/src/menu/pointer_menu_row.dart';
import 'package:chrome_foundation/src/motion/chrome_motion.dart';
import 'package:chrome_foundation/src/motion/chrome_motion_scope.dart';
import 'package:chrome_foundation/src/motion/pointer_menu_motion.dart';
import 'package:chrome_foundation/src/tokens/pointer_menu_tokens.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Opens **pointer menus**: the popup list of rows with shortcut hints,
/// disabled rows, separators and submenus that a secondary click opens at the
/// pointer, drawn and driven as the reference desktop client's `Ui::PopupMenu`
/// (the plain variant, without icons).
///
/// A menu is an overlay entry, so it is modal like a native one: a press
/// anywhere else closes it and goes no further; Escape closes it; the arrow
/// keys, Enter and Space drive it and every other key is swallowed. Rows react
/// to the pointer only once it has moved (the opening click's own release must
/// not choose the row beneath it).
///
/// - **Placement.** The body's top leading corner is 5 px from the pointer,
///   flipped and pushed in to stay inside the overlay (`PointerMenuPlacements`).
/// - **Motion.** The panel grows from the corner at the pointer
///   (`PointerMenuReveal`) and fades out linearly; both are motion roles, so
///   reduce-motion removes them.
/// - **Keys.** Down and Up move through the rows that can be chosen, wrapping,
///   with nothing selected on open; Right (Left in right-to-left) opens a
///   submenu and selects its first row, Left closes it; Escape closes the
///   submenu, then the menu.
/// - **Submenus.** A row with a submenu opens it at once on hover. While the
///   pointer travels toward it inside the aim triangle, the rows it crosses do
///   not take the highlight, until it pauses for `PointerMenuTiming.aimHold`.
/// - **Focus.** The menu takes focus while open, as a child of [focusParent]
///   so a text field that is its parent keeps its selection painted, and gives
///   it to [returnFocusTo] as the menu starts to close, before the chosen
///   row's action runs.
abstract final class PointerMenu {
  /// Opens a menu of [entries] with its corner at [globalPosition].
  ///
  /// [tokens] and [motion] are resolved by the caller: the overlay the menu
  /// lives in does not see a scope mounted around the widget that opened it.
  /// Nothing opens for [entries] with no row that can be chosen; the returned
  /// handle is then already closed.
  static PointerMenuHandle show(
    BuildContext context, {
    required Offset globalPosition,
    required List<PointerMenuEntry> entries,
    required PointerMenuTokens tokens,
    ChromeMotionData motion = ChromeMotionData.standard,
    TextDirection? textDirection,
    FocusNode? focusParent,
    FocusNode? returnFocusTo,
    VoidCallback? onClosed,
    bool rootOverlay = true,
  }) {
    final handle = PointerMenuHandle._(onClosed);
    if (!entries.any(PointerMenuNavigation.isChoosable)) {
      handle._finish();
      return handle;
    }
    final overlay = Overlay.of(context, rootOverlay: rootOverlay);
    final box = overlay.context.findRenderObject()! as RenderBox;
    final entry = OverlayEntry(
      builder: (_) => _PointerMenuRoot(
        handle: handle,
        globalPointer: globalPosition,
        pointer: box.globalToLocal(globalPosition),
        bounds: Offset.zero & box.size,
        entries: entries,
        tokens: tokens,
        motion: motion,
        textDirection: textDirection ?? Directionality.of(context),
        focusParent: focusParent,
        returnFocusTo: returnFocusTo,
      ),
    );
    handle._entry = entry;
    overlay.insert(entry);
    return handle;
  }
}

/// An open pointer menu: closes it and says when it has gone.
final class PointerMenuHandle {
  PointerMenuHandle._(this._onClosed);

  final VoidCallback? _onClosed;
  final _closed = Completer<void>();
  OverlayEntry? _entry;
  _PointerMenuRootState? _state;
  var _closeRequested = false;

  /// Whether the menu is still up (it is, while it fades out).
  bool get isOpen => !_closed.isCompleted;

  /// Completes once the menu has left the overlay.
  Future<void> get closed => _closed.future;

  /// Starts closing the menu with its fade. Does nothing once it is closing or
  /// closed.
  void close() {
    if (!isOpen) return;
    final state = _state;
    if (state == null) {
      _closeRequested = true;
    } else {
      state.hide();
    }
  }

  void _finish() {
    if (_closed.isCompleted) return;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _closed.complete();
    _onClosed?.call();
  }
}

// One open panel: the root menu or a submenu, with what it shows and where.
class _Level {
  _Level({
    required this.entries,
    required this.body,
    required this.origin,
    required this.rowTops,
    required this.show,
    this.parentRow,
  });

  final List<PointerMenuEntry> entries;
  final Rect body;
  final PointerMenuOrigin origin;

  /// The top of each entry inside the body.
  final List<double> rowTops;
  final AnimationController show;

  /// The row of the level below that opened this one.
  final int? parentRow;
  int? selected;
}

class _PointerMenuRoot extends StatefulWidget {
  const _PointerMenuRoot({
    required this.handle,
    required this.globalPointer,
    required this.pointer,
    required this.bounds,
    required this.entries,
    required this.tokens,
    required this.motion,
    required this.textDirection,
    required this.focusParent,
    required this.returnFocusTo,
  });

  final PointerMenuHandle handle;
  final Offset globalPointer;
  final Offset pointer;
  final Rect bounds;
  final List<PointerMenuEntry> entries;
  final PointerMenuTokens tokens;
  final ChromeMotionData motion;
  final TextDirection textDirection;
  final FocusNode? focusParent;
  final FocusNode? returnFocusTo;

  @override
  State<_PointerMenuRoot> createState() => _PointerMenuRootState();
}

class _PointerMenuRootState extends State<_PointerMenuRoot>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _scope = FocusScopeNode(debugLabel: 'PointerMenu');
  late final AnimationController _hide = AnimationController(
    vsync: this,
    duration: widget.motion.durationOf(MotionRole.pointerMenuHide),
  );
  final _levels = <_Level>[];

  late TextStyle _style;
  late TextScaler _scaler;
  var _measured = false;

  var _closing = false;

  // The mouse guard: rows ignore the pointer until it has moved.
  var _moved = false;
  var _motions = 0;

  // The row a press was taken on, as (level, index).
  (int, int)? _pressed;

  // Aim protection while a submenu is open.
  Offset? _aimApex;
  Timer? _aimTimer;

  @override
  void initState() {
    super.initState();
    widget.handle._state = this;
    WidgetsBinding.instance.addObserver(this);
    _hide.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.handle._finish();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closing) return;
      _scope.requestFocus();
    });
    if (widget.handle._closeRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) => hide());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _scaler = media.textScaler.clamp(
      maxScaleFactor: PointerMenuMetrics.maxTextScale,
    );
    _style = TextStyle(
      inherit: false,
      fontSize: PointerMenuMetrics.fontSize,
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      color: widget.tokens.text,
      decoration: TextDecoration.none,
      fontWeight: FontWeight.normal,
    );
    if (!_measured) {
      _measured = true;
      _pushRoot();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _aimTimer?.cancel();
    for (final level in _levels) {
      level.show.dispose();
    }
    _hide.dispose();
    _scope.dispose();
    if (identical(widget.handle._state, this)) widget.handle._state = null;
    super.dispose();
  }

  @override
  void didChangeMetrics() => _finishAtOnce();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) hide();
  }

  // --- Levels ---

  Size _sizeOf(List<PointerMenuEntry> entries) {
    var width = 0.0;
    var height = 2 * PointerMenuMetrics.verticalPadding;
    for (final entry in entries) {
      switch (entry) {
        case PointerMenuSeparator():
          height += PointerMenuMetrics.separatorHeight;
        case final PointerMenuItem item:
          height += PointerMenuMetrics.rowHeight;
          width = math.max(
            width,
            pointerMenuRowWidth(
              item: item,
              style: _style,
              textDirection: widget.textDirection,
              textScaler: _scaler,
            ),
          );
      }
    }
    return Size(
      width.clamp(PointerMenuMetrics.minWidth, PointerMenuMetrics.maxWidth),
      height,
    );
  }

  List<double> _rowTops(List<PointerMenuEntry> entries) {
    final tops = <double>[];
    var y = PointerMenuMetrics.verticalPadding;
    for (final entry in entries) {
      tops.add(y);
      y += entry is PointerMenuSeparator
          ? PointerMenuMetrics.separatorHeight
          : PointerMenuMetrics.rowHeight;
    }
    return tops;
  }

  AnimationController _showController() => AnimationController(
    vsync: this,
    duration: widget.motion.durationOf(MotionRole.pointerMenuShow),
  );

  void _pushRoot() {
    final size = _sizeOf(widget.entries);
    final placement = PointerMenuPlacements.of(
      pointer: widget.pointer,
      size: size,
      bounds: widget.bounds,
      textDirection: widget.textDirection,
    );
    _levels.add(
      _Level(
        entries: widget.entries,
        body: placement.body,
        origin: placement.origin,
        rowTops: _rowTops(widget.entries),
        show: _showController()..forward(),
      ),
    );
  }

  void _openSubmenu(int levelIndex, int row, {required bool byKey}) {
    final parent = _levels[levelIndex];
    final item = parent.entries[row] as PointerMenuItem;
    final entries = item.submenu!;
    final size = _sizeOf(entries);
    final rowTop = parent.body.top + parent.rowTops[row];
    final placement = PointerMenuPlacements.submenu(
      parent: parent.body,
      rowTop: rowTop,
      size: size,
      bounds: widget.bounds,
      textDirection: widget.textDirection,
    );
    final level = _Level(
      entries: entries,
      body: placement.body,
      origin: placement.origin,
      rowTops: _rowTops(entries),
      show: _showController()..forward(),
      parentRow: row,
    );
    if (byKey) level.selected = PointerMenuNavigation.firstEnabled(entries);
    setState(() {
      parent.selected = row;
      _levels.add(level);
    });
  }

  // Drops the levels above [levelIndex] without a fade, as the reference
  // does for a submenu.
  void _closeAbove(int levelIndex) {
    if (_levels.length <= levelIndex + 1) return;
    _aimTimer?.cancel();
    _aimApex = null;
    setState(() {
      while (_levels.length > levelIndex + 1) {
        _levels.removeLast().show.dispose();
      }
    });
  }

  // --- Pointer ---

  bool _guardOpenFor(Offset global) =>
      _moved ||
      (global - widget.globalPointer).distance >
          PointerMenuMetrics.mouseGuardDistance ||
      _motions + 1 > PointerMenuMetrics.mouseGuardMotions;

  void _noteMotion(PointerEvent event) {
    if (_moved) return;
    _motions++;
    if ((event.position - widget.globalPointer).distance >
            PointerMenuMetrics.mouseGuardDistance ||
        _motions > PointerMenuMetrics.mouseGuardMotions) {
      _moved = true;
    }
  }

  bool _aimHolds(Offset pointer, _Level child, _Level parent) {
    final apex = _aimApex;
    if (apex == null) return false;
    final x = child.body.left >= parent.body.right - 0.5
        ? child.body.left
        : child.body.right;
    final inside = PointerMenuAim.contains(
      apex: apex,
      edgeTop: Offset(x, child.body.top),
      edgeBottom: Offset(x, child.body.bottom),
      point: pointer,
    );
    if (!inside) {
      _aimApex = null;
      _aimTimer?.cancel();
      return false;
    }
    _trackAim(pointer);
    return true;
  }

  void _trackAim(Offset apex) {
    _aimApex = apex;
    _aimTimer?.cancel();
    _aimTimer = Timer(PointerMenuTiming.aimHold, () => _aimApex = null);
  }

  void _onHover(int levelIndex, int row, Offset global) {
    if (_closing || levelIndex >= _levels.length || !_guardOpenFor(global)) {
      return;
    }
    final level = _levels[levelIndex];
    if (levelIndex < _levels.length - 1) {
      final child = _levels[levelIndex + 1];
      if (child.parentRow == row) {
        _trackAim(global);
        return;
      }
      if (_aimHolds(global, child, level)) return;
      _closeAbove(levelIndex);
    }
    final entry = level.entries[row];
    if (!PointerMenuNavigation.isChoosable(entry)) {
      if (level.selected != null) setState(() => level.selected = null);
      return;
    }
    if (level.selected != row) setState(() => level.selected = row);
    if ((entry as PointerMenuItem).submenu != null &&
        _levels.length == levelIndex + 1) {
      _openSubmenu(levelIndex, row, byKey: false);
      _trackAim(global);
    }
  }

  void _onExit(int levelIndex, int row) {
    if (_closing || levelIndex >= _levels.length) return;
    final level = _levels[levelIndex];
    final hasChild = levelIndex < _levels.length - 1;
    if (!hasChild && level.selected == row) {
      setState(() => level.selected = null);
    }
  }

  bool _onPress(int levelIndex, int row) {
    if (_closing || levelIndex >= _levels.length || !_moved) return false;
    _pressed = (levelIndex, row);
    return true;
  }

  void _onRelease(int levelIndex, int row) {
    if (_pressed != (levelIndex, row) || levelIndex >= _levels.length) return;
    _pressed = null;
    final entry = _levels[levelIndex].entries[row];
    if (entry is PointerMenuItem) _choose(levelIndex, row, entry);
  }

  // --- Choosing ---

  void _choose(int levelIndex, int row, PointerMenuItem item) {
    if (_closing || !item.isEnabled) return;
    if (item.submenu != null) {
      if (_levels.length == levelIndex + 1) {
        _openSubmenu(levelIndex, row, byKey: true);
      }
      return;
    }
    hide();
    _run(item.onSelected);
  }

  static void _run(FutureOr<void> Function()? action) {
    if (action == null) return;
    void report(Object error, StackTrace stack) => FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'chrome_foundation',
        context: ErrorDescription('while running a pointer menu row'),
      ),
    );
    try {
      final result = action();
      if (result is Future<void>) unawaited(result.onError(report));
    } on Object catch (error, stack) {
      report(error, stack);
    }
  }

  // --- Keys ---

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    if (_closing) return KeyEventResult.handled;
    final key = event.logicalKey;
    final rtl = widget.textDirection == TextDirection.rtl;
    final deepest = _levels.length - 1;
    final level = _levels[deepest];
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final next = PointerMenuNavigation.step(
        level.entries,
        level.selected,
        forward: key == LogicalKeyboardKey.arrowDown,
      );
      if (next != null) setState(() => level.selected = next);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      final row = level.selected;
      if (row != null && level.entries[row] is PointerMenuItem) {
        _choose(deepest, row, level.entries[row] as PointerMenuItem);
      }
    } else if (key ==
        (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)) {
      final row = level.selected;
      if (row != null &&
          level.entries[row] is PointerMenuItem &&
          (level.entries[row] as PointerMenuItem).isEnabled &&
          (level.entries[row] as PointerMenuItem).submenu != null) {
        _openSubmenu(deepest, row, byKey: true);
      }
    } else if (key ==
        (rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft)) {
      _closeAbove(deepest - 1);
    } else if (key == LogicalKeyboardKey.escape) {
      if (deepest > 0) {
        _closeAbove(deepest - 1);
      } else {
        hide();
      }
    }
    // A popup is modal for the keyboard too: nothing reaches the field.
    return KeyEventResult.handled;
  }

  // --- Closing ---

  /// Starts the fade out and gives focus back.
  void hide() {
    if (_closing) return;
    _closing = true;
    _aimTimer?.cancel();
    _returnFocus();
    _hide.forward();
  }

  // Applied at once, not at the next microtask: the chosen row's action runs
  // straight after and must find the field focused.
  void _returnFocus() {
    final target = widget.returnFocusTo;
    if (target == null) return;
    target.requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  }

  void _finishAtOnce() {
    if (_closing) {
      return;
    }
    _closing = true;
    _returnFocus();
    widget.handle._finish();
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final panels = <Widget>[
      for (var i = 0; i < _levels.length; i++) _panel(i, _levels[i]),
    ];
    return MediaQuery(
      data: media.copyWith(textScaler: _scaler),
      child: Directionality(
        textDirection: widget.textDirection,
        child: FocusScope(
          node: _scope,
          parentNode: widget.focusParent,
          onKeyEvent: _onKey,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerHover: _noteMotion,
            onPointerMove: _noteMotion,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              scopesRoute: true,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (_) => hide(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  ...panels,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(int index, _Level level) {
    final tokens = widget.tokens;
    return Positioned.fromRect(
      rect: level.body,
      child: IgnorePointer(
        ignoring: _closing,
        child: _PointerMenuPanel(
          key: PointerMenuPanelKey(index),
          level: level,
          hide: _hide,
          tokens: tokens,
          rows: [
            for (var i = 0; i < level.entries.length; i++)
              switch (level.entries[i]) {
                PointerMenuSeparator() => _Separator(tokens: tokens),
                final PointerMenuItem item => PointerMenuRow(
                  key: PointerMenuRowKey(item.id),
                  item: item,
                  tokens: tokens,
                  style: _style,
                  highlighted: level.selected == i,
                  rippleEnabled: !widget.motion.speed.isInstant,
                  onHover: (global) => _onHover(index, i, global),
                  onExit: () => _onExit(index, i),
                  onPress: () => _onPress(index, i),
                  onRelease: () => _onRelease(index, i),
                ),
              },
          ],
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.tokens});

  final PointerMenuTokens tokens;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: tokens.background,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: SizedBox(
        height: PointerMenuMetrics.separatorLine,
        width: double.infinity,
        child: ColoredBox(color: tokens.separator),
      ),
    ),
  );
}

// One panel: its shadow, and its rows revealed through the growing frame.
class _PointerMenuPanel extends StatelessWidget {
  const _PointerMenuPanel({
    required this.level,
    required this.hide,
    required this.tokens,
    required this.rows,
    super.key,
  });

  final _Level level;
  final Animation<double> hide;
  final PointerMenuTokens tokens;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final size = level.body.size;
    final content = ColoredBox(
      color: tokens.background,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: PointerMenuMetrics.verticalPadding,
        ),
        child: Column(children: rows),
      ),
    );
    return AnimatedBuilder(
      animation: Listenable.merge([level.show, hide]),
      builder: (context, _) {
        final reveal = PointerMenuReveal.at(level.show.value);
        final frame = reveal.frame(size, level.origin);
        return Opacity(
          opacity: (reveal.opacity * (1 - hide.value)).clamp(0.0, 1.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ShadowPainter(frame: frame, tokens: tokens),
                ),
              ),
              Positioned.fill(
                child: ClipRRect(
                  clipper: _FrameClipper(frame),
                  child: CustomPaint(
                    foregroundPainter: _StripPainter(
                      frame: frame,
                      reveal: reveal,
                      color: tokens.background,
                    ),
                    child: content,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FrameClipper extends CustomClipper<RRect> {
  const _FrameClipper(this.frame);

  final Rect frame;

  @override
  RRect getClip(Size size) =>
      RRect.fromRectAndRadius(frame, PointerMenuMetrics.cornerRadius);

  @override
  bool shouldReclip(_FrameClipper old) => old.frame != frame;
}

class _ShadowPainter extends CustomPainter {
  const _ShadowPainter({required this.frame, required this.tokens});

  final Rect frame;
  final PointerMenuTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        frame.shift(PointerMenuMetrics.shadowOffset),
        PointerMenuMetrics.cornerRadius,
      ),
      Paint()
        ..color = tokens.shadow.withValues(
          alpha: tokens.shadow.a * PointerMenuMetrics.shadowOpacity,
        )
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          PointerMenuMetrics.shadowBlur / 2,
        ),
    );
  }

  @override
  bool shouldRepaint(_ShadowPainter old) =>
      old.frame != frame || old.tokens != tokens;
}

// The strip that uncovers the rows from the top: panel colour over everything
// below it, fading to nothing along its height.
class _StripPainter extends CustomPainter {
  const _StripPainter({
    required this.frame,
    required this.reveal,
    required this.color,
  });

  final Rect frame;
  final PointerMenuReveal reveal;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (reveal.contentRevealed >= 1) return;
    final top = reveal.stripTop(frame).dy;
    final strip = frame.height * PointerMenuMetrics.fadeHeight;
    canvas.drawRect(
      Rect.fromLTRB(frame.left, top, frame.right, frame.bottom),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, top + strip), [
          color.withValues(alpha: 0),
          color,
        ]),
    );
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.frame != frame ||
      old.reveal.contentRevealed != reveal.contentRevealed ||
      old.color != color;
}
