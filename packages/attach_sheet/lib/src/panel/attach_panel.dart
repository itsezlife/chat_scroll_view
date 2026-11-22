import 'dart:async';
import 'dart:math' as math;

import 'package:attach_sheet/src/host/attach_caption_dock.dart';
import 'package:attach_sheet/src/panel/attach_send_controller.dart';
import 'package:attach_sheet/src/policy/attach_panel_style.dart';
import 'package:attach_sheet/src/policy/attach_selection_header_style.dart';
import 'package:attach_sheet/src/sheet/attach_sheet.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';

/// The **attach panel**: the caption field and the counter send button.
///
/// One widget for every place a send is made: the sheet's bottom area, the
/// picker-mode viewer's bottom slot, the confirm box. A tap on Send sends; a
/// long press opens the send menu. Over the caption limit the field shakes
/// and nothing is sent.
class AttachCaptionBar extends StatefulWidget {
  /// The panel of [controller]; the send button grows from the policy's
  /// scale with [reveal] when given.
  const AttachCaptionBar({
    required this.controller,
    this.reveal,
    this.beforeSend,
    this.dock,
    this.caption,
    this.addMore,
    this.showsCount = true,
    super.key,
  });

  /// Whether Send carries the selection's count.
  final bool showsCount;

  /// The add-photo button leading the field while the keyboard is down
  /// (the camera's viewer: back to the camera for another shot); null for
  /// none. With the field focused, the keyboard up or the panel in its
  /// place, the panel button takes its place, and a tap on it is ignored.
  final VoidCallback? addMore;

  /// The field this bar edits: the panel's caption when null; the viewer's
  /// own field over the same text otherwise.
  final ComposerController? caption;

  /// The host's dock under this bar: its panel button leads the field and
  /// the field pads what the dock's place does not cover. Null: no button,
  /// and no pad (the bar's place pads the safe area).
  final AttachCaptionDock? dock;

  /// The panel's state.
  final AttachSendController controller;

  /// The caption text's inset from the pill's start while no button leads
  /// it: the pill's corner radius less the field's own end pad, so the hint
  /// starts as far in as it ends.
  static const double fieldStartInset =
      ComposerMetrics.islandRadius - ComposerMetrics.fieldEndPad;

  /// How long add-photo and the panel button take to fade in as they swap.
  static const Duration addMoreFade = Duration(milliseconds: 150);

  /// Runs before a tap on Send sends (the viewer selects the item it shows
  /// when nothing is selected).
  final VoidCallback? beforeSend;

  /// The panel coming in, 0 to 1; null for a panel that is just there.
  final Animation<double>? reveal;

  @override
  State<AttachCaptionBar> createState() => _AttachCaptionBarState();
}

class _AttachCaptionBarState extends State<AttachCaptionBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _$shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  AttachSendController get _send => widget.controller;
  ComposerController get _caption => widget.caption ?? _send.caption;

  @override
  void initState() {
    super.initState();
    _send.refusals.addListener(_refused);
    _send.caption.focusNode.addListener(_focused);
    _caption.focusNode.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(AttachCaptionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.caption ?? _send.caption;
    if (!identical(old, _caption)) {
      old.focusNode.removeListener(_focusChanged);
      _caption.focusNode.addListener(_focusChanged);
    }
  }

  // The add-photo button follows the field's focus.
  void _focusChanged() {
    if (widget.addMore != null && mounted) setState(() {});
  }

  // Whether the keyboard (or the panel in its place) is up or coming: the
  // field focused, the panel up, or the keyboard's inset showing.
  bool _keyboardUp(AttachCaptionDock? dock) =>
      _caption.focusNode.hasFocus ||
      (dock?.panelUp ?? false) ||
      MediaQuery.viewInsetsOf(context).bottom > 0;

  // A tap on add-photo while the caption is open does nothing.
  void _addMore(AttachCaptionDock? dock) {
    if (_keyboardUp(dock)) return;
    widget.addMore?.call();
  }

  @override
  void dispose() {
    _send.refusals.removeListener(_refused);
    _send.caption.focusNode.removeListener(_focused);
    _caption.focusNode.removeListener(_focusChanged);
    _$shake.dispose();
    super.dispose();
  }

  void _refused() => unawaited(_$shake.forward(from: 0));

  void _focused() {
    if (!_send.caption.focusNode.hasFocus) return;
    if (!_send.policy.expandsOnCaptionFocus) return;
    unawaited(AttachSheetController.maybeOf(context)?.expand());
  }

  // The chat's composer view over the caption, with the dock's panel
  // button leading it.
  Widget _composer(
    BuildContext context, {
    required AttachCaptionDock? dock,
    required double bottomPad,
  }) {
    final strings = ChromeStringsScope.attachOf(context);
    final composerStrings = ChromeStringsScope.of(context).composer;
    final from = _send.counterFrom;
    final panelUp = dock?.panelUp ?? false;
    final addMore = widget.addMore;
    // With add-photo, it and the panel button share the leading place: one
    // while the keyboard is down, the other while it is up, each fading in.
    final addPhotoShown = addMore != null && !_keyboardUp(dock);
    return ComposerView(
      key: const ValueKey('attach-caption'),
      controller: _caption,
      autofocus: false,
      onFieldTap: widget.caption == null
          ? _send.captionTapped
          : () => _send.fieldTapped(_caption, dock),
      onFieldPointerDown: dock?.onFieldPointerDown,
      onFieldPointerEnd: dock?.onFieldPointerEnd,
      safeAreaBottom: bottomPad,
      hintText: strings.captionPlaceholder,
      // With no button leading it, the hint keeps off the pill's round
      // start.
      fieldStartInset: AttachCaptionBar.fieldStartInset,
      spec: ComposerSpec(
        messageLengthLimit: _send.captionLimit,
        messageLengthCounterFrom: switch (from) {
          final from? => math.max(0, from),
          null => null,
        },
        actions: [
          // The caption's panel toggle, as the chat's: the emoji page in the
          // keyboard's place, or back.
          if (addMore != null)
            ActionDescriptor(
              id: 'attach-caption-add-photo',
              icon: ChromeIconId.addPhoto,
              semanticLabel: strings.captionAddPhoto,
              placement: ActionPlacement.leading,
              visible: addPhotoShown,
              onTap: () => _addMore(dock),
              wrap: _fadeIn,
            ),
          if (dock != null)
            ActionDescriptor(
              id: 'attach-caption-panel',
              icon: panelUp ? ChromeIconId.keyboard : ChromeIconId.emoji,
              semanticLabel: panelUp
                  ? composerStrings.showKeyboardAction
                  : composerStrings.showPanelAction,
              placement: ActionPlacement.leading,
              visible: !addPhotoShown,
              onTap: dock.togglePanel,
              wrap: addMore == null ? null : _fadeIn,
            ),
        ],
      ),
    );
  }

  // A leading button that takes the place fades in.
  static Widget _fadeIn(BuildContext context, Widget button) =>
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AttachCaptionBar.addMoreFade,
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: button,
      );

  @override
  Widget build(BuildContext context) => switch (widget.dock) {
    // The dock's pad goes under the island and under Send alike, so Send
    // stays on the island's baseline with the keyboard down, up, or the
    // panel in its place.
    final dock? => ListenableBuilder(
      listenable: dock.changes,
      builder: (context, _) => ValueListenableBuilder<double>(
        valueListenable: dock.fieldBottomPad,
        builder: (context, pad, _) => _bar(context, dock: dock, bottomPad: pad),
      ),
    ),
    null => _bar(context, dock: null, bottomPad: 0),
  };

  Widget _bar(
    BuildContext context, {
    required AttachCaptionDock? dock,
    required double bottomPad,
  }) => Material(
    type: MaterialType.transparency,
    // The chat's own composer island: the field in its floating pill, with
    // the island's margins and glass, and Send beside it.
    child: Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _$shake,
              builder: (context, field) => Transform.translate(
                key: const ValueKey('attach-caption-shake'),
                offset: Offset(
                  6 *
                      math.sin(_$shake.value * 6 * math.pi) *
                      (1 - _$shake.value),
                  0,
                ),
                child: field,
              ),
              child: _composer(context, dock: dock, bottomPad: bottomPad),
            ),
          ),
          // On the island's baseline: the composer's bottom margin and the
          // dock's pad under it.
          Padding(
            padding: EdgeInsets.only(
              bottom: ComposerMetrics.islandBottomGap + bottomPad,
            ),
            child: switch (widget.reveal) {
              final reveal? => AnimatedBuilder(
                animation: reveal,
                child: AttachSendButton(
                  controller: _send,
                  beforeSend: widget.beforeSend,
                  showsCount: widget.showsCount,
                ),
                builder: (context, button) {
                  final from = _send.policy.panel.sendButtonFromScale;
                  return Transform.scale(
                    key: const ValueKey('attach-send-reveal'),
                    scale: from + (1 - from) * reveal.value,
                    child: button,
                  );
                },
              ),
              null => AttachSendButton(
                controller: _send,
                beforeSend: widget.beforeSend,
                showsCount: widget.showsCount,
              ),
            },
          ),
        ],
      ),
    ),
  );
}

/// The send button with the selection's count, bouncing when it changes. A
/// tap sends; a long press opens the send menu.
class AttachSendButton extends StatefulWidget {
  /// The send button of [controller].
  const AttachSendButton({
    required this.controller,
    this.beforeSend,
    this.showsCount = true,
    super.key,
  });

  /// The panel's state.
  final AttachSendController controller;

  /// Whether it carries the selection's count.
  final bool showsCount;

  /// Runs before a tap sends.
  final VoidCallback? beforeSend;

  @override
  State<AttachSendButton> createState() => _AttachSendButtonState();
}

class _AttachSendButtonState extends State<AttachSendButton>
    with TickerProviderStateMixin {
  late final AnimationController _$bounce;
  late final AnimationController _$roll;
  late int _count = widget.controller.selection.length;
  // The count rolling from [_from] to [_count]; 0 is no text.
  late int _from = _count;

  @override
  void initState() {
    super.initState();
    _$bounce = AnimationController.unbounded(vsync: this, value: 1);
    _$roll = AnimationController(vsync: this, value: 1);
    widget.controller.selection.changes.addListener(_counted);
  }

  @override
  void dispose() {
    widget.controller.selection.changes.removeListener(_counted);
    _$bounce.dispose();
    _$roll.dispose();
    super.dispose();
  }

  Future<void> _counted() async {
    final count = widget.controller.selection.length;
    if (count == _count) return;
    final grew = count > _count;
    final speed = ChromeMotionScope.of(context).speed;
    setState(() {
      // A roll in flight starts again from the value it shows most.
      _from = _$roll.value < 0.5 ? _from : _count;
      _count = count;
    });
    _$roll.value = 0;
    unawaited(
      _$roll
          .animateTo(
            1,
            duration: speed.scale(AttachCountBadge.roll),
            curve: Curves.easeOutQuint,
          )
          .orCancel
          .then((_) {}, onError: (Object _) {}),
    );
    if (count == 0) return;
    final bounce = widget.controller.policy.panel.countBounce;
    if (speed.isInstant) return;
    final peak = grew ? bounce.up : bounce.down;
    try {
      if (bounce.out case final out?) {
        final spec = out.withSpeed(speed);
        await _$bounce
            .animateTo(peak, duration: spec.duration, curve: spec.curve)
            .orCancel;
      } else {
        _$bounce.value = peak;
      }
      // Unbounded, so an overshooting back curve passes 1 and returns.
      final back = bounce.back.withSpeed(speed);
      await _$bounce
          .animateTo(1, duration: back.duration, curve: back.curve)
          .orCancel;
      _$bounce.value = 1;
    } on TickerCanceled {
      return;
    }
  }

  void _openMenu() {
    final send = widget.controller;
    final items = send.sendMenu;
    if (items.isEmpty) return;
    final strings = ChromeStringsScope.attachOf(context);
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    unawaited(
      AttachMenu.show(
        context,
        anchor: anchor,
        entries: [
          for (final item in items)
            AttachMenuEntry(
              id: 'send-${item.name}',
              label: switch (item) {
                AttachSendMenuItem.silent => strings.sendSilently,
                AttachSendMenuItem.schedule => strings.schedule,
                AttachSendMenuItem.whenOnline => strings.sendWhenOnline,
                AttachSendMenuItem.captionAbove =>
                  send.options.value.captionAbove
                      ? strings.captionBelow
                      : strings.captionAbove,
                AttachSendMenuItem.highQuality =>
                  send.options.value.highQuality
                      ? strings.standardQuality
                      : strings.highQuality,
                AttachSendMenuItem.spoiler =>
                  send.allSpoilered
                      ? strings.disableSpoiler
                      : strings.enableSpoiler,
              },
              onSelected: (context) => send.runSendMenu(item, context),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final strings = ChromeStringsScope.attachOf(context);
    final size = widget.controller.policy.panel.sendButtonSize;
    return Semantics(
      button: true,
      label: strings.sendAction,
      child: GestureDetector(
        key: const ValueKey('attach-send'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.beforeSend?.call();
          widget.controller.send();
        },
        onLongPress: _openMenu,
        onSecondaryTap: _openMenu,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: palette.onAccent,
                    size: size * 0.5,
                  ),
                ),
              ),
              // The count sits on the button's top-start corner, its top on
              // the button's top, its centre on the button's start edge. It
              // stays while it rolls away to nothing.
              PositionedDirectional(
                start: 0,
                top: 0,
                child: FractionalTranslation(
                  translation: Offset(
                    Directionality.of(context) == TextDirection.rtl
                        ? 0.5
                        : -0.5,
                    0,
                  ),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_$bounce, _$roll]),
                    builder: (context, _) {
                      // Eased by its own animation (ease out quint).
                      final t = _$roll.value;
                      final old = _from == 0 ? '' : '$_from';
                      final text = _count == 0 ? '' : '$_count';
                      // Shown while either end has text, scaled by it.
                      final shown =
                          (old.isEmpty ? 0.0 : 1 - t) +
                          (text.isEmpty ? 0.0 : t);
                      if (shown <= 0 || !widget.showsCount) {
                        return const SizedBox.shrink();
                      }
                      final badge = AttachCountBadge(from: old, to: text, t: t);
                      return Transform.scale(
                        key: const ValueKey('attach-send-bounce'),
                        scale: _$bounce.value * shown,
                        // Where the policy opens the preview from the
                        // count, a tap on it opens the selected-items
                        // preview (and closes it), not a send.
                        child:
                            widget.controller.policy.selectionHeader.opensFrom(
                                  AttachPreviewEntry.sendCount,
                                ) &&
                                widget.controller.header.previewHosted
                            ? GestureDetector(
                                key: const ValueKey('attach-send-count-tap'),
                                behavior: HitTestBehavior.opaque,
                                onTap: widget.controller.header.togglePreview,
                                child: badge,
                              )
                            : badge,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The send button's count: the button's fill with a ring of the sheet's
/// background around it, so it reads as cut out of what it overlaps, and
/// the count in white bold 12.
///
/// The count rolls from [from] to [to] at [t] (0 to 1) as the reference's
/// animated text does: aligned from the end, a digit that stays slides to
/// its new place, a digit that goes drops [moveAmplitude] of the text size
/// and fades, a digit that comes drops in from that far above and fades in;
/// the badge's width follows the text's, at least [diameter].
class AttachCountBadge extends StatelessWidget {
  /// The badge of [to], rolling from [from] at [t].
  const AttachCountBadge({
    required this.to,
    this.from = '',
    this.t = 1,
    super.key,
  });

  /// The count shown, '' for none.
  final String to;

  /// The count it rolls from, '' for none.
  final String from;

  /// How far the roll is, 0 to 1 (already eased).
  final double t;

  /// The badge's least size (`max(9 + textWidth, 18)`).
  static const double diameter = 18;

  /// What the count's width is padded by.
  static const double padding = 9;

  /// The ring in the sheet's background around the fill.
  static const double ring = 2;

  /// The text size of the count.
  static const double fontSize = 12;

  /// How far a digit moves as it comes or goes, in text sizes.
  static const double moveAmplitude = 0.3;

  /// How long the count takes to roll to a new value (ease out quint).
  static const Duration roll = Duration(milliseconds: 320);

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final tokens = ChromeThemeScope.attachOf(context);
    final style = ChromeTypography.of(context).copyWith(
      color: palette.onAccent,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1,
    );
    final direction = Directionality.of(context);
    double widthOf(String text) => text.isEmpty
        ? 0
        : (TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
          )..layout()).width;
    final oldWidth = widthOf(from);
    final newWidth = widthOf(to);
    final width = oldWidth + (newWidth - oldWidth) * t;
    final inner = math.max(padding + width, diameter);
    const move = fontSize * moveAmplitude;

    // Digits from the end: the i-th from the end of each.
    final children = <Widget>[];
    final count = math.max(from.length, to.length);
    for (var i = 0; i < count; i++) {
      final o = i < from.length ? from[from.length - 1 - i] : null;
      final n = i < to.length ? to[to.length - 1 - i] : null;
      // Where the digit's end sits from the text's end, in each.
      final oldEnd = widthOf(from.substring(math.max(0, from.length - i)));
      final newEnd = widthOf(to.substring(math.max(0, to.length - i)));
      Widget digit(
        String c, {
        required double end,
        required double dy,
        required double opacity,
      }) => Positioned(
        right: end,
        top: dy,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Text(c, style: style),
        ),
      );
      if (o != null && o == n) {
        children.add(
          digit(o, end: oldEnd + (newEnd - oldEnd) * t, dy: 0, opacity: 1),
        );
        continue;
      }
      if (o != null && t < 1) {
        children.add(digit(o, end: oldEnd, dy: move * t, opacity: 1 - t));
      }
      if (n != null) {
        children.add(digit(n, end: newEnd, dy: -move * (1 - t), opacity: t));
      }
    }
    return Container(
      key: const ValueKey('attach-send-count'),
      width: inner + 2 * ring,
      height: diameter + 2 * ring,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(diameter / 2 + ring),
        border: Border.all(color: tokens.background, width: ring),
      ),
      child: ClipRect(
        child: SizedBox(
          width: width,
          height: fontSize,
          child: Stack(clipBehavior: Clip.none, children: children),
        ),
      ),
    );
  }
}

/// The overflow button for a page's header: the policy's overflow entries
/// that show for the selection.
class AttachOverflowButton extends StatelessWidget {
  /// The overflow button of [controller].
  const AttachOverflowButton({required this.controller, super.key});

  /// The panel's state.
  final AttachSendController controller;

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.attachOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    return Semantics(
      button: true,
      label: strings.moreOptions,
      child: GestureDetector(
        key: const ValueKey('attach-overflow'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final box = context.findRenderObject()! as RenderBox;
          final anchor = box.localToGlobal(Offset.zero) & box.size;
          final send = controller;
          final many = send.selection.length > 1;
          final high = send.options.value.highQuality;
          unawaited(
            AttachMenu.show(
              context,
              anchor: anchor,
              entries: [
                for (final item in send.overflow)
                  AttachMenuEntry(
                    id: 'overflow-${item.name}',
                    label: switch (item) {
                      AttachOverflowItem.openExternal => strings.openExternal,
                      AttachOverflowItem.sendAsFiles =>
                        many ? strings.sendAsFiles : strings.sendAsFile,
                      AttachOverflowItem.withoutGrouping =>
                        strings.sendWithoutGrouping,
                      AttachOverflowItem.spoiler =>
                        send.allSpoilered
                            ? strings.disableSpoiler
                            : strings.enableSpoiler,
                      AttachOverflowItem.quality =>
                        high ? strings.standardQuality : strings.highQuality,
                      AttachOverflowItem.highQuality => strings.sendInHd,
                      AttachOverflowItem.captionAbove =>
                        send.options.value.captionAbove
                            ? strings.captionBelow
                            : strings.captionAbove,
                    },
                    onSelected: (_) async => send.runOverflow(item),
                  ),
              ],
            ),
          );
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(Icons.more_vert, color: palette.iconIdle),
        ),
      ),
    );
  }
}

/// One entry of an [AttachMenu].
@immutable
final class AttachMenuEntry {
  /// An entry labelled [label].
  const AttachMenuEntry({
    required this.id,
    required this.label,
    required this.onSelected,
  });

  /// Its key, `attach-menu-<id>`.
  final String id;

  /// Its label.
  final String label;

  /// Runs when it is chosen, after the menu has closed, with the context the
  /// menu was opened from.
  final Future<void> Function(BuildContext context) onSelected;
}

/// The sheet's small menus (the send menu, the overflow menu): a column of
/// entries over a scrim, placed next to the control that opened it.
abstract final class AttachMenu {
  /// Shows [entries] next to [anchor] (global) and runs the chosen one.
  static Future<void> show(
    BuildContext context, {
    required Rect anchor,
    required List<AttachMenuEntry> entries,
  }) async {
    final chosen = await Navigator.of(context).push<AttachMenuEntry>(
      PageRouteBuilder<AttachMenuEntry>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: const Color(0x00000000),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (menuContext, _, _) => ChromeTextRoot(
          child: _AttachMenuView(anchor: anchor, entries: entries),
        ),
      ),
    );
    if (chosen == null || !context.mounted) return;
    await chosen.onSelected(context);
  }
}

class _AttachMenuView extends StatelessWidget {
  const _AttachMenuView({required this.anchor, required this.entries});

  final Rect anchor;
  final List<AttachMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          right: math.max(8, size.width - anchor.right),
          bottom: anchor.top < size.height / 2
              ? null
              : math.max(8, size.height - anchor.top + 8),
          top: anchor.top < size.height / 2 ? anchor.bottom + 8 : null,
          child: Container(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 16)],
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries)
                  Semantics(
                    button: true,
                    child: GestureDetector(
                      key: ValueKey('attach-menu-${entry.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(entry),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(
                          entry.label,
                          style: ChromeTypography.of(
                            context,
                          ).copyWith(color: palette.onSurface, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The panel taking the tab bar's place while something is selected: it
/// comes in by the policy's reveal (Android: a fade and the send button
/// growing from 0.2; iOS: a rise of 44 and a fade) and leaves the same way
/// when the selection empties.
class AttachPanelReveal extends StatefulWidget {
  /// The reveal of [controller]'s panel.
  const AttachPanelReveal({required this.controller, super.key});

  /// The panel's state.
  final AttachSendController controller;

  @override
  State<AttachPanelReveal> createState() => _AttachPanelRevealState();
}

class _AttachPanelRevealState extends State<AttachPanelReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _$shown = AnimationController(
    vsync: this,
    value: widget.controller.selection.isEmpty ? 0 : 1,
  );
  Curve _curve = Curves.linear;

  @override
  void initState() {
    super.initState();
    widget.controller.selection.changes.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.selection.changes.removeListener(_changed);
    _$shown.dispose();
    super.dispose();
  }

  void _changed() {
    final show = widget.controller.selection.isNotEmpty;
    final spec = widget.controller.policy.panel.reveal.withSpeed(
      ChromeMotionScope.of(context).speed,
    );
    _curve = spec.curve;
    unawaited(_$shown.animateTo(show ? 1 : 0, duration: spec.duration));
  }

  @override
  Widget build(BuildContext context) {
    final rise = widget.controller.policy.panel.revealRise;
    final curved = CurvedAnimation(parent: _$shown, curve: _curve);
    return AnimatedBuilder(
      animation: _$shown,
      // The composer's island floats over the page as it does over the
      // chat; the sheet's bottom fade is under it, not a band.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AttachCaptionBar(
            controller: widget.controller,
            reveal: curved,
            dock: widget.controller.captionDock,
          ),
          // Under the caption: the dock's place (the keyboard's or the
          // panel's, the safe area in it); with no dock, the safe area, which
          // a raised keyboard covers (the sheet lifts the bar by its inset).
          switch (widget.controller.captionDock) {
            final dock? => dock.buildPlace(context),
            null => SizedBox(
              height: MediaQuery.viewInsetsOf(context).bottom > 0
                  ? 0
                  : MediaQuery.paddingOf(context).bottom,
            ),
          },
        ],
      ),
      builder: (context, panel) {
        final t = _curve.transform(_$shown.value);
        return Offstage(
          offstage: _$shown.value == 0,
          child: IgnorePointer(
            ignoring: _$shown.value < 1,
            child: Opacity(
              key: const ValueKey('attach-panel'),
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, rise * (1 - t)),
                child: panel,
              ),
            ),
          ),
        );
      },
    );
  }
}
