import 'dart:async';
import 'dart:math' as math;

import 'package:attach_sheet/src/panel/attach_send_controller.dart';
import 'package:attach_sheet/src/policy/attach_panel_style.dart';
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
  const AttachCaptionBar({required this.controller, this.reveal, super.key});

  /// The panel's state.
  final AttachSendController controller;

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

  @override
  void initState() {
    super.initState();
    _send.refusals.addListener(_refused);
    _send.caption.focusNode.addListener(_focused);
  }

  @override
  void dispose() {
    _send.refusals.removeListener(_refused);
    _send.caption.focusNode.removeListener(_focused);
    _$shake.dispose();
    super.dispose();
  }

  void _refused() => unawaited(_$shake.forward(from: 0));

  void _focused() {
    if (!_send.caption.focusNode.hasFocus) return;
    if (!_send.policy.expandsOnCaptionFocus) return;
    unawaited(AttachSheetController.maybeOf(context)?.expand());
  }

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.attachOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final from = _send.counterFrom;
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedBuilder(
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
                    child: ComposerFormField(
                      key: const ValueKey('attach-caption'),
                      controller: _send.caption,
                      minLines: 1,
                      maxLines: 6,
                      style: TextStyle(color: palette.onSurface, fontSize: 16),
                      decoration: InputDecoration.collapsed(
                        hintText: strings.captionPlaceholder,
                        hintStyle: TextStyle(color: palette.onSurfaceMuted),
                      ),
                    ),
                  ),
                  if (from != null)
                    ComposerLengthCounter(
                      key: const ValueKey('attach-caption-counter'),
                      controller: _send.caption,
                      limit: _send.captionLimit,
                      shake: _$shake,
                      visibleFromLength: math.max(0, from),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            switch (widget.reveal) {
              final reveal? => AnimatedBuilder(
                animation: reveal,
                child: AttachSendButton(controller: _send),
                builder: (context, button) {
                  final from = _send.policy.panel.sendButtonFromScale;
                  return Transform.scale(
                    key: const ValueKey('attach-send-reveal'),
                    scale: from + (1 - from) * reveal.value,
                    child: button,
                  );
                },
              ),
              null => AttachSendButton(controller: _send),
            },
          ],
        ),
      ),
    );
  }
}

/// The send button with the selection's count, bouncing when it changes. A
/// tap sends; a long press opens the send menu.
class AttachSendButton extends StatefulWidget {
  /// The send button of [controller].
  const AttachSendButton({required this.controller, super.key});

  /// The panel's state.
  final AttachSendController controller;

  @override
  State<AttachSendButton> createState() => _AttachSendButtonState();
}

class _AttachSendButtonState extends State<AttachSendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _$bounce;
  late int _count = widget.controller.selection.length;

  @override
  void initState() {
    super.initState();
    _$bounce = AnimationController.unbounded(vsync: this, value: 1);
    widget.controller.selection.changes.addListener(_counted);
  }

  @override
  void dispose() {
    widget.controller.selection.changes.removeListener(_counted);
    _$bounce.dispose();
    super.dispose();
  }

  Future<void> _counted() async {
    final count = widget.controller.selection.length;
    if (count == _count) return;
    final grew = count > _count;
    setState(() => _count = count);
    if (count == 0) return;
    final bounce = widget.controller.policy.panel.countBounce;
    final speed = ChromeMotionScope.of(context).speed;
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
        onTap: () => widget.controller.send(),
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
              if (_count > 0)
                PositionedDirectional(
                  end: -4,
                  bottom: -4,
                  child: AnimatedBuilder(
                    animation: _$bounce,
                    builder: (context, badge) => Transform.scale(
                      key: const ValueKey('attach-send-bounce'),
                      scale: _$bounce.value,
                      child: badge,
                    ),
                    child: Container(
                      key: const ValueKey('attach-send-count'),
                      constraints: const BoxConstraints(minWidth: 18),
                      height: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palette.surfaceRaised,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: palette.accent, width: 1.5),
                      ),
                      child: Text(
                        '$_count',
                        style: TextStyle(
                          color: palette.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
        pageBuilder: (menuContext, _, _) =>
            _AttachMenuView(anchor: anchor, entries: entries),
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
                          style: TextStyle(
                            color: palette.onSurface,
                            fontSize: 15,
                          ),
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
    final tokens = ChromeThemeScope.attachOf(context);
    final padding = MediaQuery.paddingOf(context);
    final rise = widget.controller.policy.panel.revealRise;
    final curved = CurvedAnimation(parent: _$shown, curve: _curve);
    return AnimatedBuilder(
      animation: _$shown,
      child: ColoredBox(
        color: tokens.background,
        child: Padding(
          padding: EdgeInsets.only(bottom: padding.bottom),
          child: AttachCaptionBar(
            controller: widget.controller,
            reveal: curved,
          ),
        ),
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
