import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_pages/src/overlay/chrome_overlay_scopes.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/preview/content_preview_item.dart';
import 'package:panel_pages/src/preview/content_preview_layout.dart';
import 'package:panel_pages/src/preview/content_preview_menu.dart';
import 'package:panel_shell/panel_shell.dart';

/// The host's handle on the content previews of its panel and its sheets:
/// the content library they read their menus from, and the one preview that
/// is up, which a back press closes ([dismiss]).
///
/// A preview stands over the whole window in an overlay, outside any route,
/// so the system back reaches whatever the host routes it to (its panel's
/// back handling) and not the preview. The host asks [dismiss] first and
/// stops there when it answers true, as the reference client closes the
/// preview, menu and all, on back.
///
/// Created and disposed by the host, after the pages and sheets that use it.
final class ContentPreviewController {
  /// A controller whose previews read [library] (null: no item that depends
  /// on the library is offered).
  ContentPreviewController({this.library});

  /// The content library the previews' menus read: whether a sticker is a
  /// favourite, a GIF saved. Read only; every edit is asked of the host.
  final ContentLibrary? library;

  final _open = listen.ValueNotifier<bool>(false);
  ContentPreviewSession? _session;
  var _disposed = false;

  /// Whether a preview is up.
  listen.ValueListenable<bool> get isOpen => _open;

  /// Closes the preview that is up, menu and all; true when there was one.
  bool dismiss() {
    final session = _session;
    if (session == null || !session.isOpen.value) return false;
    session.close();
    return true;
  }

  /// Takes the preview that is up away at once, and forgets it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _session?.cancel();
    _session = null;
  }

  // A new preview replaces one still up (a sheet opened over the panel's).
  void _attach(ContentPreviewSession session) {
    if (_disposed) return;
    final previous = _session;
    _session = session;
    if (previous != null && !identical(previous, session)) previous.cancel();
    _open.value = true;
    session.isOpen.addListener(() {
      if (!session.isOpen.value && identical(_session, session)) {
        _session = null;
        if (!_disposed) _open.value = false;
      }
    });
  }
}

/// A content preview: a sticker, GIF or custom emoji shown large over the
/// window while a finger holds its cell, with the menu of what can be done
/// with it.
///
/// It is the reference mobile client's `ContentPreviewViewer`, as one
/// [CatalogLongPressSession] every surface opens the same way: the panel's
/// sticker grid (its favourites and recents too), its GIF page and its
/// custom emoji cells, and a pack sheet's grid. A unicode emoji is never
/// previewed.
///
/// ## Opening
///
/// The opener begins it when its cell has been held [touchHoldDelay] (a
/// finger) or [pointerHoldDelay] (a mouse: the desktop client's drag time),
/// with the cell the press is on. It comes up over [showDuration], linearly,
/// growing from its centre as it fades in over a dim of the window
/// ([dimDark] or [dimLight] by the theme, at [dimAlpha] of its own alpha).
/// A finger feels it ([HapticFeedback.vibrate]).
///
/// ## While the finger is down
///
/// - A sticker or custom emoji follows the finger: over another cell that
///   is previewed (`itemAt`), it shows that one instead, with a light tick
///   ([HapticFeedback.selectionClick]), and a menu that was up goes.
/// - A GIF does not switch: moving up drags it up to [gifSwipeLimit], with a
///   rubber band, and at [gifSwipeMenu] its menu opens; an arrow over it
///   says so until then.
/// - The menu opens by itself after [stickerMenuDelay] (a sticker of a pack,
///   or a custom emoji) or [gifMenuDelay] (a GIF), when it has an item, with
///   the same haptic as the opening. A blur of the window fades in under it.
///
/// ## Ending
///
/// - Lifting before the menu is up closes the preview: nothing is sent (the
///   long press already kept the tap from the cell).
/// - Lifting after the menu is up keeps both; an item chosen asks the opener
///   (see [ContentPreviewActions]) and closes the preview, as does a press
///   anywhere else, or [close] (the host's back, through
///   [ContentPreviewController.dismiss]).
/// - A mouse gets the desktop client's preview: no menu, and lifting closes
///   it. Its actions are the cell's context menu
///   ([ContentPreviewMenu.entriesOf]).
/// - [openMenu] opens the menu at once (after [instantMenuDelay]): a tap on a
///   cell of a sheet that shows the preview and its actions straight away.
///
/// ## Hold
///
/// The preview stands outside the panel's box: the opener's hold on the
/// panel's auto-hide is released by the session as it starts to close.
final class ContentPreviewSession implements CatalogLongPressSession {
  ContentPreviewSession._({
    required ContentPreviewItem item,
    required this.assets,
    required this.actions,
    required this.library,
    required this.kind,
    required this.keyboardHeight,
    required ContentPreviewItem? Function(Offset globalPosition)? itemAt,
    required PanelPageHold? hold,
  }) : _item = ValueNotifier(item),
       _itemAt = itemAt,
       _hold = hold;

  /// Opens a preview of [item] over the window of [context], drawn through
  /// [assets], whose menu offers what [actions] gives.
  ///
  /// - [library]: what the menu reads (favourite, saved); null offers none
  ///   of the items that depend on it.
  /// - [itemAt]: the previewed item under a global point, or null; how a
  ///   sticker or custom emoji follows the finger to another cell. A grid
  ///   over a `PanelCatalogViewport` answers with its controller's `leafAt`
  ///   and [ContentPreviewItem.ofLeaf]. Null: the preview stays on [item].
  /// - [kind]: the pointer that pressed; a mouse gets no menu.
  /// - [openMenu]: the menu comes up at once, whatever [kind].
  /// - [hold]: the opener's hold on the panel's auto-hide, released as the
  ///   preview starts to close.
  /// - [controller]: the host's handle, which closes the preview on back.
  /// - [keyboardHeight]: the height the reference assumes a keyboard takes,
  ///   which the preview stays above where the window is tall enough.
  ///
  /// Places the preview in the nearest root `Overlay` and re-provides the
  /// chrome theme, strings, motion and direction of [context].
  static ContentPreviewSession show({
    required BuildContext context,
    required ContentPreviewItem item,
    required AssetCacheScope assets,
    required ContentPreviewActions actions,
    ContentLibrary? library,
    ContentPreviewItem? Function(Offset globalPosition)? itemAt,
    PointerDeviceKind kind = PointerDeviceKind.touch,
    bool openMenu = false,
    PanelPageHold? hold,
    ContentPreviewController? controller,
    double keyboardHeight = ContentPreviewLayout.defaultKeyboardHeight,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final scopes = ChromeOverlayScopes.capture(context);
    final session = ContentPreviewSession._(
      item: item,
      assets: assets,
      actions: actions,
      library: library,
      kind: kind,
      keyboardHeight: keyboardHeight,
      itemAt: itemAt,
      hold: hold,
    );
    session._entry = OverlayEntry(
      // In the text fields' tap group: a press that closes the preview is not
      // a press outside the composer.
      builder: (context) => scopes.wrap(
        TextFieldTapRegion(child: _PreviewOverlay(session: session)),
      ),
    );
    overlay.insert(session._entry!);
    controller?._attach(session);
    if (kind != PointerDeviceKind.mouse) unawaited(HapticFeedback.vibrate());
    if (openMenu) {
      session._scheduleMenu(instantMenuDelay);
    } else {
      session._scheduleMenuFor(item);
    }
    return session;
  }

  /// How long a finger holds a cell before the preview opens:
  /// `runOnUIThread(openPreviewRunnable, 200)`.
  static const Duration touchHoldDelay = Duration(milliseconds: 200);

  /// How long a mouse button holds a cell before the preview opens: the
  /// desktop client's `QApplication::startDragTime()`.
  static const Duration pointerHoldDelay = Duration(milliseconds: 500);

  /// How long the preview takes to come up or go: `showProgress += dt / 120`.
  static const Duration showDuration = Duration(milliseconds: 120);

  /// When the menu of a sticker or custom emoji opens on its own:
  /// `runOnUIThread(showSheetRunnable, 1300)`.
  static const Duration stickerMenuDelay = Duration(milliseconds: 1300);

  /// When a GIF's menu opens on its own: `runOnUIThread(showSheetRunnable,
  /// 2000)`.
  static const Duration gifMenuDelay = Duration(milliseconds: 2000);

  /// When the menu of a preview opened by a tap comes up: the reference's
  /// `menuOpenDelay` of one frame.
  static const Duration instantMenuDelay = Duration(milliseconds: 16);

  /// How far up a GIF can be dragged: `-dp(60)`.
  static const double gifSwipeLimit = 60;

  /// How far up a GIF is dragged when its menu opens: `-dp(55)`.
  static const double gifSwipeMenu = 55;

  /// The rubber band's factor: `rubberYPoisition(currentMoveY, dp(200))`.
  static const double gifSwipeFactor = 200;

  /// The dim over a dark theme: `0x71000000`.
  static const Color dimDark = Color(0x71000000);

  /// The dim over a light theme: `0x64E6E6E6`.
  static const Color dimLight = Color(0x64E6E6E6);

  /// The alpha the dim is drawn at, of 255, when the preview is up:
  /// `backgroundDrawable.setAlpha((int) (180 * showProgress))`, which a
  /// `ColorDrawable` multiplies into its colour's own alpha.
  static const int dimAlpha = 180;

  /// How strong the blur under the menu is at its end. Not traced: the
  /// reference blurs a downscaled bitmap of the window
  /// (`ScrimOptions.makeGlobalBlurBitmaps`).
  static const double menuBlurSigma = 12;

  /// The draws the content is resized from: the cache's.
  final AssetCacheScope assets;

  /// What the menu offers.
  final ContentPreviewActions actions;

  /// What the menu reads.
  final ContentLibrary? library;

  /// The pointer that opened the preview.
  final PointerDeviceKind kind;

  /// The height a keyboard is taken to have.
  final double keyboardHeight;

  final ValueNotifier<ContentPreviewItem> _item;
  final ContentPreviewItem? Function(Offset globalPosition)? _itemAt;
  final PanelPageHold? _hold;
  final _open = listen.ValueNotifier<bool>(true);
  // The menu's items while it is up, or null.
  final _menu = ValueNotifier<List<ContentPreviewAction>?>(null);
  // How far a GIF was dragged up (0 down to -[gifSwipeLimit]).
  final _swipe = ValueNotifier<double>(0);
  OverlayEntry? _entry;
  Timer? _menuTimer;
  double? _lastY;
  var _closing = false;
  // Set by the overlay once the preview is all the way up: a GIF is dragged
  // only then, as the reference's `showProgress == 1`.
  var _up = false;

  /// What the preview shows now.
  ContentPreviewItem get item => _item.value;

  /// The items of the menu while it is up, or null.
  List<ContentPreviewAction>? get menu => _menu.value;

  @override
  listen.ValueListenable<bool> get isOpen => _open;

  // --- The gesture ----------------------------------------------------------

  @override
  void update(LongPressMoveUpdateDetails details) {
    if (_closing) return;
    if (item.kind == ContentPreviewKind.gif) {
      _swipeGif(details.globalPosition.dy);
      return;
    }
    final next = _itemAt?.call(details.globalPosition);
    if (next == null || next.key == item.key) return;
    _menuTimer?.cancel();
    _menu.value = null;
    _item.value = next;
    _scheduleMenuFor(next);
    if (kind != PointerDeviceKind.mouse) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  // `currentMoveY` follows the finger, kept within [-limit, 0], and the GIF
  // is drawn at its rubber-banded value; past the menu's mark the menu opens.
  void _swipeGif(double y) {
    if (_menu.value != null || !_up) return;
    final last = _lastY;
    _lastY = y;
    if (last == null) return;
    _moveY = (_moveY + y - last).clamp(-gifSwipeLimit, 0);
    _swipe.value = _rubber(_moveY);
    if (_moveY <= -gifSwipeMenu) _showMenu();
  }

  var _moveY = 0.0;

  /// The reference's `rubberYPoisition`: how far a drag of [offset] moves
  /// the GIF.
  static double _rubber(double offset) {
    final delta = offset.abs();
    final moved =
        (1 - 1 / (delta * 0.55 / gifSwipeFactor + 1)) * gifSwipeFactor;
    return offset < 0 ? -moved : moved;
  }

  @override
  void end(LongPressEndDetails details) {
    if (_closing || _menu.value != null) return;
    close();
  }

  @override
  void cancel() {
    if (_entry != null) _finish();
  }

  // --- The menu -------------------------------------------------------------

  // A sticker opens its menu by itself only when it has a pack (the
  // reference's `newSet != null`); a custom emoji always; a mouse never.
  void _scheduleMenuFor(ContentPreviewItem item) {
    if (kind == PointerDeviceKind.mouse) return;
    switch (item.kind) {
      case ContentPreviewKind.gif:
        _scheduleMenu(gifMenuDelay);
      case ContentPreviewKind.customEmoji:
        _scheduleMenu(stickerMenuDelay);
      case ContentPreviewKind.sticker when item.pack != null:
        _scheduleMenu(stickerMenuDelay);
      case ContentPreviewKind.sticker:
        break;
    }
  }

  void _scheduleMenu(Duration delay) {
    _menuTimer?.cancel();
    _menuTimer = Timer(delay, _showMenu);
  }

  void _showMenu() {
    _menuTimer?.cancel();
    if (_closing || _menu.value != null) return;
    final items = ContentPreviewMenu.of(item, actions, library: library);
    if (items.isEmpty) return;
    _menu.value = items;
    if (kind != PointerDeviceKind.mouse) unawaited(HapticFeedback.vibrate());
  }

  void _choose(ContentPreviewAction action) {
    if (_closing) return;
    final chosen = item;
    close();
    ContentPreviewMenu.perform(action, chosen, actions);
  }

  // --- Closing --------------------------------------------------------------

  /// Closes the preview, menu and all, over [showDuration].
  void close() {
    if (_closing) return;
    _closing = true;
    _menuTimer?.cancel();
    _hold?.release();
    _open.value = false;
  }

  // At once: the opener went, or the closing is over.
  void _finish() {
    _closing = true;
    _menuTimer?.cancel();
    _hold?.release();
    if (_open.value) _open.value = false;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}

class _PreviewOverlay extends StatefulWidget {
  const _PreviewOverlay({required this.session});

  final ContentPreviewSession session;

  @override
  State<_PreviewOverlay> createState() => _PreviewOverlayState();
}

class _PreviewOverlayState extends State<_PreviewOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: ContentPreviewSession.showDuration,
  );
  // The blur under the menu: `blurProgress += 16 / 120f` a frame.
  late final AnimationController _blur = AnimationController(
    vsync: this,
    duration: ContentPreviewSession.showDuration,
  );

  ContentPreviewSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _session._open.addListener(_onOpenChanged);
    _session._menu.addListener(_onMenuChanged);
    unawaited(
      _show.forward().whenComplete(() {
        if (mounted && _session._open.value) _session._up = true;
      }),
    );
  }

  @override
  void dispose() {
    _session._open.removeListener(_onOpenChanged);
    _session._menu.removeListener(_onMenuChanged);
    _show.dispose();
    _blur.dispose();
    super.dispose();
  }

  void _onOpenChanged() {
    if (_session._open.value) return;
    setState(() {});
    unawaited(_blur.reverse());
    _show.reverse().whenComplete(() {
      if (mounted) _session._finish();
    });
  }

  void _onMenuChanged() {
    if (_session._menu.value != null) {
      unawaited(_blur.forward());
    } else {
      unawaited(_blur.reverse());
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final palette = ChromeThemeScope.paletteOf(context);
    final media = MediaQuery.maybeOf(context);
    final dim = palette.brightness == Brightness.dark
        ? ContentPreviewSession.dimDark
        : ContentPreviewSession.dimLight;
    return IgnorePointer(
      ignoring: !session._open.value,
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: Listenable.merge([
            _show,
            _blur,
            session._item,
            session._swipe,
            session._menu,
          ]),
          builder: (context, _) {
            final item = session.item;
            final emoji = item.emoji;
            final layout = ContentPreviewLayout(
              window: constraints.biggest,
              padding: media?.viewPadding ?? EdgeInsets.zero,
              kind: item.kind,
              contentSize: item.size,
              emoji: emoji != null,
              swipe: session._swipe.value,
              keyboardHeight: session.keyboardHeight,
            );
            final shown = _show.value;
            final blur = _blur.value;
            final menu = session._menu.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (blur > 0)
                  BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: ContentPreviewSession.menuBlurSigma * blur,
                      sigmaY: ContentPreviewSession.menuBlurSigma * blur,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ColoredBox(
                  color: dim.withAlpha(
                    (dim.a * ContentPreviewSession.dimAlpha * shown).round(),
                  ),
                ),
                // A press anywhere else closes the preview, and goes no
                // further.
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => session.close(),
                ),
                Positioned.fromRect(
                  rect: layout.content,
                  child: Transform.scale(
                    scale: shown,
                    child: Opacity(
                      opacity: shown,
                      child: _PreviewContent(
                        item: item,
                        size: layout.content.size,
                        assets: session.assets,
                      ),
                    ),
                  ),
                ),
                if (emoji != null)
                  Positioned.fromRect(
                    rect: layout.emoji,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: shown,
                        child: Text(
                          emoji,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: ContentPreviewLayout.emojiFontSize,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (item.kind == ContentPreviewKind.gif &&
                    menu == null &&
                    session.kind != PointerDeviceKind.mouse)
                  Positioned(
                    left: layout.square.center.dx - _SwipeArrow.width / 2,
                    top:
                        layout.square.top -
                        (17 + 6 * session._moveY / 60) -
                        _SwipeArrow.height,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity:
                            shown * (1 + session._moveY / 60).clamp(0.0, 1.0),
                        child: _SwipeArrow(color: palette.onSurface),
                      ),
                    ),
                  ),
                if (menu != null)
                  CustomSingleChildLayout(
                    delegate: _MenuPlacement(
                      top: layout.menuTop,
                      bottom: media?.viewPadding.bottom ?? 0,
                    ),
                    child: Opacity(
                      opacity: blur,
                      child: _PreviewMenu(
                        item: item,
                        actions: menu,
                        onChoose: session._choose,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Centres the menu across the window with its top at [top], or higher
/// when it would pass the window's [bottom] padding: the popup window the
/// reference shows is kept on screen by the system.
final class _MenuPlacement extends SingleChildLayoutDelegate {
  const _MenuPlacement({required this.top, required this.bottom});

  final double top;
  final double bottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (size.width - childSize.width) / 2,
    math.max(0, math.min(top, size.height - bottom - childSize.height)),
  );

  @override
  bool shouldRelayout(_MenuPlacement oldDelegate) =>
      oldDelegate.top != top || oldDelegate.bottom != bottom;
}

class _PreviewContent extends StatelessWidget {
  const _PreviewContent({
    required this.item,
    required this.size,
    required this.assets,
  });

  final ContentPreviewItem item;
  final Size size;
  final AssetCacheScope assets;

  @override
  Widget build(BuildContext context) {
    final density = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final gif = item.kind == ContentPreviewKind.gif;
    return ContentView(
      content: item.key,
      scope: assets,
      semanticLabel: item.spokenName,
      preset: AssetPreset(
        size: size,
        spec: AssetSpec.atDensity(
          logicalWidth: size.width,
          logicalHeight: size.height,
          devicePixelRatio: density,
        ),
        profile: AssetProfile(
          animate: true,
          cornerRadius: gif ? ContentPreviewLayout.gifRadius : 0,
        ),
      ),
    );
  }
}

/// The arrow over a GIF that says a drag up opens its menu. The reference
/// draws an asset (`slideUpDrawable`); this is a chevron of about its size.
class _SwipeArrow extends StatelessWidget {
  const _SwipeArrow({required this.color});

  static const double width = 24;
  static const double height = 12;

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(width, height),
    painter: _ChevronPainter(color),
  );
}

final class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(2, size.height - 2)
        ..lineTo(size.width / 2, 2)
        ..lineTo(size.width - 2, size.height - 2),
      pen,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}

/// The menu card under the preview: the reference's `ActionBarPopupWindow`
/// of `ActionBarMenuSubItem`s, without their icons.
class _PreviewMenu extends StatelessWidget {
  const _PreviewMenu({
    required this.item,
    required this.actions,
    required this.onChoose,
  });

  /// `ActionBarMenuSubItem` is `dp(48)` tall.
  static const double itemExtent = 48;

  /// The popup's corner radius, `dp(12)`.
  static const double radius = 12;

  /// The popup's padding, `dp(8)`.
  static const double padding = 8;

  /// An item's text inset, `dp(18)`, and size, 16.
  static const double itemInset = 18;
  static const double fontSize = 16;

  /// The narrowest the card is. Not traced.
  static const double minWidth = 200;

  final ContentPreviewItem item;
  final List<ContentPreviewAction> actions;
  final ValueChanged<ContentPreviewAction> onChoose;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final strings = ChromeStringsScope.panelOf(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: minWidth),
          child: IntrinsicWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final action in actions)
                    _PreviewMenuItem(
                      label: ContentPreviewMenu.labelOf(action, item, strings),
                      color: ContentPreviewMenu.isAttention(action, item)
                          ? palette.destructive
                          : palette.onSurface,
                      onTap: () => onChoose(action),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewMenuItem extends StatelessWidget {
  const _PreviewMenuItem({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: _PreviewMenu.itemExtent,
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: _PreviewMenu.itemInset),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _PreviewMenu.fontSize,
            decoration: TextDecoration.none,
            color: color,
          ),
        ),
      ),
    ),
  );
}
