import 'package:chat_composer/src/capabilities/composer_clock.dart';
import 'package:chat_composer/src/draft_options/draft_link_page.dart';
import 'package:chat_composer/src/draft_options/draft_link_part.dart';
import 'package:chat_composer/src/draft_options/draft_link_rows.dart';
import 'package:chat_composer/src/draft_options/draft_options_gate.dart';
import 'package:chat_composer/src/draft_options/draft_options_host.dart';
import 'package:chat_composer/src/draft_options/draft_options_policy.dart';
import 'package:chat_composer/src/draft_options/draft_options_session.dart';
import 'package:chat_composer/src/draft_options/draft_options_web_menu_policy.dart';
import 'package:chat_composer/src/draft_options/overlay_op.dart';
import 'package:chat_composer/src/link_preview/link_preview_dismissal.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// What the draft options open on: the host's current link [value], the
/// link's [page], the draft's [text] and its [links] in text order.
///
/// The web's menu reads it when it opens, which for a hover is a moment
/// after the pointer came onto the strip, so the host answers with the
/// draft as it is then.
@immutable
final class DraftOptionsInput {
  /// The draft as the options open on it.
  const DraftOptionsInput({
    required this.value,
    required this.page,
    this.text = model.RichText.empty,
    this.links = const [],
  });

  /// The link part as the host holds it.
  final DraftLinkPart value;

  /// Where the link's page stands.
  final LinkPreviewState page;

  /// The draft's text.
  final model.RichText text;

  /// The text's links, in text order.
  final List<Uri> links;
}

/// What closed the web's draft options menu, as its `webMenuClosed` event
/// names it.
enum DraftOptionsWebMenuCloseTrigger {
  /// A press outside the menu, on its transparent catcher.
  outside,

  /// A mouse left the strip and the menu for the policy's grace.
  leave,

  /// A secondary click.
  secondaryClick,

  /// A row applied its choice.
  choice,

  /// Link previews were denied while the menu was up.
  denied,

  /// The menu's owner went away.
  disposed,
}

/// Opens and closes the web's **draft options menu**: a menu anchored at the
/// link preview strip, with no overlay, no scrim and no live preview, whose
/// rows are the link page's and whose every choice is reported to the
/// [host] at once.
///
/// One per composer, kept by the host, which wires the strip to it: the
/// strip's open action to [open] and its hover report to [hover]. With a
/// mouse the menu opens once the pointer has rested on the strip for the
/// policy's hover delay; a tap (or a click) opens it at once. It closes on a
/// press outside, on a choice and, when a mouse opened it, on a secondary
/// click or when the pointer has been off the strip and the menu for the
/// policy's grace. Another link is chosen by tapping it in the text, not
/// from the menu.
///
/// Layout follows the window's width class (the side the menu prefers,
/// live), style and interaction the input class at the open: a hover is a
/// mouse's, a tap takes `ChromeInputClass.of`.
///
/// Each open is a [DraftOptionsSession] of the web policy (live apply) with
/// a [DraftLinkPage] over it, so the rows, their guard and their events are
/// the link page's.
final class DraftOptionsWebMenuController {
  /// A controller of the web [policy] reporting to [host], opening on what
  /// [input] answers (nothing opens when it has no draft link).
  ///
  /// [correlation] gives the ids of its events (the chat); [dismissal] is
  /// the composer's link preview dismissal, which the remove row applies as
  /// the strip's cross does; [mediaOf] reads a page's media for the size
  /// row.
  DraftOptionsWebMenuController({
    required this.policy,
    required this.host,
    required this.input,
    ComposerClock clock = ComposerClock.system,
    ChatCorrelation Function()? correlation,
    this.dismissal,
    this.mediaOf,
  }) : _clock = clock,
       _correlation = correlation,
       _gate = DraftOptionsGate(clock: clock, correlation: correlation);

  /// The key of the menu's surface.
  static const Key menuKey = ValueKey('draftOptionsWebMenu');

  /// The key of the transparent catcher around the menu.
  static const Key catcherKey = ValueKey('draftOptionsWebMenuCatcher');

  /// The web's draft options rules; the menu's are its `menu`.
  final DraftOptionsPolicy$Web policy;

  /// Where edits go.
  final DraftOptionsHost host;

  /// The draft the menu opens on, read at the open; null when the draft has
  /// no link (a hover that outlived the strip's card).
  final DraftOptionsInput? Function() input;

  /// What the remove row turns off; null when the host keeps no dismissal.
  final LinkPreviewDismissal? dismissal;

  /// The host's reading of a page's media for the size row.
  final DraftLinkMediaReader? mediaOf;

  final ComposerClock _clock;
  final ChatCorrelation Function()? _correlation;
  final DraftOptionsGate _gate;
  _OpenMenu? _open;
  bool _disposed = false;
  // The pointer over the strip (as the strip reports it) and over the menu.
  bool _$overStrip = false;
  bool _$overMenu = false;
  ComposerTimer? _$hoverTimer;
  ComposerTimer? _$leaveTimer;

  DraftOptionsWebMenuPolicy get _menu => policy.menu;

  /// The open menu's session, or null when none is up. A session that is
  /// closing stays here until the menu is gone.
  DraftOptionsSession? get session => _open?.session;

  /// Whether a menu is up (closing included).
  bool get isOpen => _open != null;

  /// Whether the chat allows link previews. Turned off while the menu is
  /// up, it closes the menu (trigger `denied`) and, once it is gone, reports
  /// the preview removed; while off, the menu does not open.
  bool get linkPreviewsAllowed => _gate.allowed;
  set linkPreviewsAllowed(bool allowed) {
    if (allowed == _gate.allowed) return;
    _gate.allowed = allowed;
    if (!allowed) close(DraftOptionsWebMenuCloseTrigger.denied);
  }

  /// The link's page moved to [state]; the open menu's rows follow.
  set page(LinkPreviewState state) => _open?.session.pageState = state;

  /// A tap or a click on the strip at [stripRect] (global): opens the menu
  /// at once; true when it opened.
  ///
  /// Refused while link previews are denied, a menu is up or there is no
  /// draft link; dropped within [DraftOptionsPolicy.openGuard] of the
  /// accepted open.
  bool open(BuildContext context, Rect stripRect) =>
      _openAt(context, stripRect, hovered: false);

  /// A mouse came onto the strip at [stripRect] (global), or left it
  /// (null). Resting on it for the policy's hover delay opens the menu;
  /// leaving it closes a menu a mouse opened once the pointer is off the
  /// menu too, for the policy's grace.
  void hover(BuildContext context, Rect? stripRect) {
    if (_disposed) return;
    if (stripRect == null) {
      _$overStrip = false;
      _$hoverTimer?.cancel();
      _$hoverTimer = null;
      _scheduleLeave();
      return;
    }
    _$overStrip = true;
    _cancelLeave();
    if (_open != null || _$hoverTimer != null) return;
    _$hoverTimer = _clock.after(_menu.hoverDelay, () {
      _$hoverTimer = null;
      if (!_$overStrip || !context.mounted) return;
      _openAt(context, stripRect, hovered: true);
    });
  }

  /// Closes the open menu by [trigger], with its motion; nothing when none
  /// is up or it is closing.
  void close(DraftOptionsWebMenuCloseTrigger trigger) {
    final open = _open;
    if (open == null || open.session.isClosing) return;
    open.trigger = trigger;
    open.session.close(switch (trigger) {
      DraftOptionsWebMenuCloseTrigger.outside ||
      DraftOptionsWebMenuCloseTrigger.leave ||
      DraftOptionsWebMenuCloseTrigger.secondaryClick =>
        DraftOptionsCloseTrigger.outside,
      DraftOptionsWebMenuCloseTrigger.choice => DraftOptionsCloseTrigger.apply,
      DraftOptionsWebMenuCloseTrigger.denied => DraftOptionsCloseTrigger.denied,
      DraftOptionsWebMenuCloseTrigger.disposed =>
        DraftOptionsCloseTrigger.disposed,
    });
  }

  /// Takes an open menu away at once (trigger `disposed`) and opens no more.
  void dispose() {
    if (_disposed) return;
    close(DraftOptionsWebMenuCloseTrigger.disposed);
    _disposed = true;
    _$hoverTimer?.cancel();
    _cancelLeave();
  }

  // --- Opening ---

  bool _openAt(BuildContext context, Rect stripRect, {required bool hovered}) {
    if (_disposed) return false;
    final now = _gate.admit(isOpen: _open != null);
    if (now == null) return false;
    final draft = input();
    if (draft == null) {
      _gate.refuse(DraftOptionsOpenRefusal.noDraft);
      return false;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    final origin = switch (overlay.context.findRenderObject()) {
      final RenderBox box when box.hasSize => box.localToGlobal(Offset.zero),
      _ => Offset.zero,
    };
    final inputClass = hovered
        ? ChromeInputClass.mouse
        : ChromeInputClass.of(context);
    final widthClass = ChromeWidthClass.of(context);
    late final _OpenMenu open;
    final session = DraftOptionsSession(
      policy: policy,
      host: host,
      part: DraftPart.link,
      initial: draft.value,
      page: draft.page,
      links: draft.links,
      origin: stripRect,
      clock: _clock,
      correlation: _correlation,
      onClose: (_) => _closed(open),
    );
    final linkPage = DraftLinkPage(
      session: session,
      hasText: draft.text.plain.trim().isNotEmpty,
      dismissal: dismissal,
      mediaOf: mediaOf,
      clock: _clock,
      correlation: _correlation,
    );
    final side = _menu.sideFor(widthClass);
    _emit(
      OverlayOp.webMenuOpened,
      () => {
        'inputClass': inputClass.name,
        'widthClass': widthClass.name,
        'trigger': hovered ? 'hover' : 'tap',
        'side': side.name,
      },
    );
    final entry = OverlayEntry(
      builder: (context) => _WebMenu(
        menu: _menu,
        page: linkPage,
        strip: stripRect.shift(-origin),
        style: _menu.styleFor(inputClass),
        shown: open.shown,
        passesPress: (position) => _passesPress(open, position),
        onRow: (row) => _row(open, row),
        onHover: _menuHovered,
        onDismiss: close,
        onGone: () => _gone(open),
      ),
    );
    open = _open = _OpenMenu(
      session: session,
      page: linkPage,
      entry: entry,
      inputClass: inputClass,
      strip: stripRect.shift(-origin),
      openedAt: now,
    );
    overlay.insert(entry);
    return true;
  }

  /// Whether a press at `position` (in the overlay) passes the catcher to
  /// what is under it: within the open guard, so a burst of taps on the
  /// strip opens once and does not close again, and over the strip when a
  /// mouse opened the menu, so the strip keeps its hover.
  bool _passesPress(_OpenMenu open, Offset position) =>
      _gate.guards(open.openedAt) ||
      (open.inputClass == ChromeInputClass.mouse &&
          open.strip.contains(position));

  // --- Rows ---

  void _row(_OpenMenu open, DraftLinkRow row) {
    final session = open.session;
    final before = session.value.value;
    open.page.tap(row);
    // An inert or guarded tap changes nothing; the remove row closes the
    // session itself, which reports as a choice.
    if (session.isClosing || session.value.value == before) return;
    close(DraftOptionsWebMenuCloseTrigger.choice);
  }

  // --- Leaving ---

  void _menuHovered(bool inside) {
    _$overMenu = inside;
    if (inside) {
      _cancelLeave();
    } else {
      _scheduleLeave();
    }
  }

  void _scheduleLeave() {
    final open = _open;
    if (open == null ||
        open.session.isClosing ||
        open.inputClass != ChromeInputClass.mouse ||
        _$overStrip ||
        _$overMenu ||
        _$leaveTimer != null) {
      return;
    }
    _$leaveTimer = _clock.after(_menu.leaveGrace, () {
      _$leaveTimer = null;
      if (_$overStrip || _$overMenu) return;
      close(DraftOptionsWebMenuCloseTrigger.leave);
    });
  }

  void _cancelLeave() {
    _$leaveTimer?.cancel();
    _$leaveTimer = null;
  }

  // --- Closing ---

  void _closed(_OpenMenu open) {
    final trigger = open.trigger ??= DraftOptionsWebMenuCloseTrigger.choice;
    _cancelLeave();
    _$overMenu = false;
    _emit(OverlayOp.webMenuClosed, () => {'trigger': trigger.name});
    if (trigger == DraftOptionsWebMenuCloseTrigger.disposed) {
      _gone(open);
      return;
    }
    open.shown.value = false;
  }

  void _gone(_OpenMenu open) {
    if (open.removed) return;
    open.removed = true;
    open.entry.remove();
    if (identical(_open, open)) _open = null;
    if (open.trigger == DraftOptionsWebMenuCloseTrigger.denied) {
      open.session.reportRemoved();
    }
    // After the frame that drops the entry: its builders still listen.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      open.session.dispose();
      open.shown.dispose();
    });
  }

  void _emit(OverlayOp op, Map<String, Object> Function() fields) =>
      _gate.emit(ChatEventLevel.debug, op, fields);
}

final class _OpenMenu {
  _OpenMenu({
    required this.session,
    required this.page,
    required this.entry,
    required this.inputClass,
    required this.strip,
    required this.openedAt,
  });

  final DraftOptionsSession session;
  final DraftLinkPage page;
  final OverlayEntry entry;
  final ChromeInputClass inputClass;

  /// The strip in the overlay's coordinates.
  final Rect strip;
  final DateTime openedAt;
  final ValueNotifier<bool> shown = ValueNotifier(true);

  DraftOptionsWebMenuCloseTrigger? trigger;
  bool removed = false;
}

/// The menu's skin: a transparent catcher over the window and the menu at
/// its placement, revealed and hidden by [shown].
class _WebMenu extends StatefulWidget {
  const _WebMenu({
    required this.menu,
    required this.page,
    required this.strip,
    required this.style,
    required this.shown,
    required this.passesPress,
    required this.onRow,
    required this.onHover,
    required this.onDismiss,
    required this.onGone,
  });

  final DraftOptionsWebMenuPolicy menu;
  final DraftLinkPage page;
  final Rect strip;
  final DraftOptionsMenuStyle style;
  final ValueListenable<bool> shown;
  final bool Function(Offset position) passesPress;
  final ValueChanged<DraftLinkRow> onRow;
  final ValueChanged<bool> onHover;
  final ValueChanged<DraftOptionsWebMenuCloseTrigger> onDismiss;
  final VoidCallback onGone;

  @override
  State<_WebMenu> createState() => _WebMenuState();
}

class _WebMenuState extends State<_WebMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: widget.menu.reveal.duration,
  );
  late final Animation<double> _curved = CurvedAnimation(
    parent: _reveal,
    curve: widget.menu.reveal.curve,
  );
  late final Animation<double> _scale = Tween<double>(
    begin: widget.menu.revealScaleFrom,
    end: 1,
  ).animate(_curved);

  @override
  void initState() {
    super.initState();
    widget.shown.addListener(_onShown);
    _reveal.forward();
  }

  @override
  void dispose() {
    widget.shown.removeListener(_onShown);
    _reveal.dispose();
    super.dispose();
  }

  void _onShown() {
    if (widget.shown.value) return;
    _reveal.reverse().whenCompleteOrCancel(() {
      if (mounted) widget.onGone();
    });
  }

  void _onCatcherDown(PointerDownEvent event) => widget.onDismiss(
    event.buttons & kSecondaryButton != 0
        ? DraftOptionsWebMenuCloseTrigger.secondaryClick
        : DraftOptionsWebMenuCloseTrigger.outside,
  );

  void _onMenuDown(PointerDownEvent event) {
    if (event.buttons & kSecondaryButton == 0) return;
    widget.onDismiss(DraftOptionsWebMenuCloseTrigger.secondaryClick);
  }

  @override
  Widget build(BuildContext context) => ChromeTextRoot(
    child: ValueListenableBuilder(
      valueListenable: widget.shown,
      builder: (context, shown, menu) => Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              // A closing menu lets presses outside it through.
              ignoring: !shown,
              child: _Catcher(
                key: DraftOptionsWebMenuController.catcherKey,
                passes: widget.passesPress,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onCatcherDown,
                ),
              ),
            ),
          ),
          ?menu,
        ],
      ),
      child: ListenableBuilder(
        listenable: widget.page.changes,
        builder: (context, _) => _placed(context),
      ),
    ),
  );

  Widget _placed(BuildContext context) {
    final page = widget.page;
    final style = widget.style;
    final metrics = style.rowMetrics;
    final strings = ChromeStringsScope.composerOf(context).draftOptions;
    final textStyle = ChromeTypography.of(
      context,
    ).copyWith(fontSize: metrics.fontSize);
    final rows = page.rows;
    final labels = [for (final row in rows) row.label.of(strings)];
    final size = Size(
      metrics.minWidthBeyondLabel + _widest(context, labels, textStyle),
      style.verticalPadding * 2 + metrics.height * rows.length,
    );
    final direction = Directionality.of(context);
    final placement = widget.menu.place(
      strip: widget.strip,
      size: size,
      bounds: Offset.zero & MediaQuery.sizeOf(context),
      side: widget.menu.sideFor(ChromeWidthClass.of(context)),
      textDirection: direction,
    );
    final rowPolicy = page.policy.copyWith(rowMetrics: metrics, ink: style.ink);
    final column = Padding(
      padding: EdgeInsets.symmetric(vertical: style.verticalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed)
            DraftLinkRowView(
              state: row,
              label: labels[i],
              policy: rowPolicy,
              style: textStyle,
              onTap: () => widget.onRow(row.row),
            ),
        ],
      ),
    );
    return Positioned.fromRect(
      rect: placement.rect,
      child: MouseRegion(
        onEnter: (_) => widget.onHover(true),
        onExit: (_) => widget.onHover(false),
        child: Listener(
          onPointerDown: _onMenuDown,
          child: ScaleTransition(
            scale: _scale,
            alignment: placement.origin,
            child: _surface(context, column),
          ),
        ),
      ),
    );
  }

  Widget _surface(BuildContext context, Widget child) {
    final style = widget.style;
    final radius = BorderRadius.circular(style.cornerRadius);
    switch (style.surface) {
      case DraftOptionsMenuSurface.glass:
        // The glass fades through its own opacity: an opacity layer above a
        // backdrop filter would show the bare tint until the fade ends.
        return AnimatedBuilder(
          animation: _curved,
          builder: (context, child) => GlassSurface(
            key: DraftOptionsWebMenuController.menuKey,
            material: style.glass,
            cornerRadius: style.cornerRadius,
            opacity: _curved.value.clamp(0, 1),
            child: child!,
          ),
          child: child,
        );
      case DraftOptionsMenuSurface.solid:
        final palette = ChromeThemeScope.of(context).palette;
        return FadeTransition(
          opacity: _curved,
          child: DecoratedBox(
            key: DraftOptionsWebMenuController.menuKey,
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: radius,
              boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 8)],
            ),
            child: ClipRRect(borderRadius: radius, child: child),
          ),
        );
    }
  }

  static double _widest(
    BuildContext context,
    List<String> labels,
    TextStyle style,
  ) {
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest;
  }
}

/// Lets a hit through to what is under it where [passes] answers true for
/// its position (the catcher fills the overlay, so in the overlay's
/// coordinates); takes it elsewhere.
class _Catcher extends SingleChildRenderObjectWidget {
  const _Catcher({required this.passes, super.child, super.key});

  final bool Function(Offset position) passes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCatcher(passes);

  @override
  void updateRenderObject(BuildContext context, _RenderCatcher renderObject) =>
      renderObject.passes = passes;
}

class _RenderCatcher extends RenderProxyBox {
  _RenderCatcher(this.passes);

  bool Function(Offset position) passes;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !passes(position) && super.hitTest(result, position: position);
}
