import 'dart:async';
import 'dart:math' as math;

import 'package:chat_composer/src/draft_options/draft_options_desktop_box.dart';
import 'package:chat_composer/src/draft_options/draft_options_key_focus.dart';
import 'package:chat_composer/src/draft_options/draft_options_session.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// The draft options as a desktop modal box: the page's [title], the live
/// [preview] and the link page's [rows] pinned under it, then Cancel and
/// Save, laid out by [box].
///
/// The skin of `DraftOptionsPolicy$Desktop` inside a `DraftOptionsOverlay`,
/// over the session's commit on save: Save is the session's apply (it
/// reports the copy and closes), Cancel its cancel (the copy is dropped).
/// Enter and Escape, focus into the box and back to the field, and the
/// close on a click outside are the overlay's and the scrim's.
///
/// The box fades in beside the scrim's dim and out once the [scrim]
/// closes, by [DraftOptionsDesktopBox.fadeIn] and
/// [DraftOptionsDesktopBox.fadeOut] at the chrome motion's speed (at once
/// under an instant one, a reduce-motion setting). An option change
/// re-lays it out at once: nothing here animates its size. Each motion is
/// reported through [DraftOptionsSession.reportMotion].
///
/// Tab walks the rows top to bottom, then Save, then Cancel, though Cancel
/// stands first: Save is the box's answer, the one a keyboard reaches
/// first.
class DraftOptionsBox extends StatefulWidget {
  /// The box of [session] over [scrim].
  const DraftOptionsBox({
    required this.box,
    required this.session,
    required this.scrim,
    required this.preview,
    this.title,
    this.rows,
    super.key,
  });

  /// The key of the box's surface.
  static const Key boxKey = ValueKey('draftOptionsBox');

  /// The key of the band holding Cancel and Save.
  static const Key buttonsKey = ValueKey('draftOptionsBoxButtons');

  /// The box's sizes and motion.
  final DraftOptionsDesktopBox box;

  /// The open the box edits.
  final DraftOptionsSession session;

  /// The scrim under the box, whose close starts the box's fade out.
  final ChromeScrimController scrim;

  /// The live preview, as tall as its messages and their margins.
  final Widget preview;

  /// The page's title; null for none.
  final String? title;

  /// The link page's rows; null for none.
  final Widget? rows;

  @override
  State<DraftOptionsBox> createState() => _DraftOptionsBoxState();
}

class _DraftOptionsBoxState extends State<DraftOptionsBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this);
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _fade,
    curve: widget.box.fadeIn.curve,
    reverseCurve: widget.box.fadeOut.curve.flipped,
  );
  var _started = false;
  var _closing = false;

  DraftOptionsSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    widget.scrim.addListener(_onScrim);
    _session.value.addListener(_onChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final spec = widget.box.fadeIn.withSpeed(_speed);
    _report(DraftOptionsMotionPhase.open, spec.duration);
    _fade.duration = spec.duration;
    if (spec.duration == Duration.zero) {
      _fade.value = 1;
    } else {
      unawaited(_fade.forward());
    }
  }

  @override
  void dispose() {
    widget.scrim.removeListener(_onScrim);
    _session.value.removeListener(_onChange);
    _eased.dispose();
    _fade.dispose();
    super.dispose();
  }

  ChromeMotionSpeed get _speed => ChromeMotionScope.of(context).speed;

  void _onScrim() {
    final scrim = widget.scrim;
    if (_closing || !scrim.isClosing || scrim.isDone) return;
    _closing = true;
    final spec = widget.box.fadeOut.withSpeed(_speed);
    _report(DraftOptionsMotionPhase.close, spec.duration);
    _fade.reverseDuration = spec.duration;
    if (spec.duration == Duration.zero) {
      _fade.value = 0;
    } else {
      unawaited(_fade.reverse());
    }
  }

  void _onChange() {
    if (_session.isClosing) return;
    _report(
      DraftOptionsMotionPhase.change,
      widget.box.optionChange.withSpeed(_speed).duration,
    );
  }

  void _report(DraftOptionsMotionPhase phase, Duration duration) =>
      _session.reportMotion(
        phase,
        duration,
        reduceMotion: _speed == ChromeMotionSpeed.instant,
      );

  @override
  Widget build(BuildContext context) {
    final box = widget.box;
    final palette = ChromeThemeScope.paletteOf(context);
    final radius = BorderRadius.circular(box.radius);
    final window = MediaQuery.sizeOf(context);
    final title = widget.title;
    final rows = widget.rows;
    return Center(
      child: FadeTransition(
        opacity: _eased,
        child: ConstrainedBox(
          constraints: BoxConstraints.tightFor(width: box.width).copyWith(
            maxHeight: math.max(0, window.height - 2 * box.windowInset),
          ),
          child: DecoratedBox(
            key: DraftOptionsBox.boxKey,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: radius,
              boxShadow: [
                BoxShadow(color: palette.shadow, blurRadius: box.shadowBlur),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ?switch (title) {
                      final title? => _title(context, title),
                      null => null,
                    },
                    // Only the preview gives way to a short window: the
                    // rows and the buttons stay pinned.
                    Flexible(
                      child: SingleChildScrollView(child: widget.preview),
                    ),
                    ?switch (rows) {
                      final rows? => FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: FocusTraversalGroup(child: rows),
                      ),
                      null => null,
                    },
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: _buttons(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context, String title) {
    final box = widget.box;
    final palette = ChromeThemeScope.paletteOf(context);
    return SizedBox(
      height: box.titleHeight,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: box.titleStart,
          end: box.titleStart,
          top: box.titleTop,
        ),
        child: Semantics(
          header: true,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ChromeTypography.of(context).copyWith(
              color: palette.onSurface,
              fontSize: box.titleFontSize,
              fontWeight: box.titleWeight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttons() {
    final box = widget.box;
    final strings = ChromeStringsScope.composerOf(context).draftOptions;
    final ink = _session.policy.linkPage.ink;
    return Padding(
      key: DraftOptionsBox.buttonsKey,
      padding: EdgeInsetsDirectional.fromSTEB(
        box.buttonBandPadding,
        box.buttonBandPadding,
        box.buttonBandPadding,
        box.buttonBandPadding,
      ),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FocusTraversalOrder(
              order: const NumericFocusOrder(2),
              child: DraftOptionsBoxButton(
                label: strings.cancel,
                box: box,
                ink: ink,
                onPressed: _session.cancel,
              ),
            ),
            SizedBox(width: box.buttonGap),
            FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: DraftOptionsBoxButton(
                label: strings.save,
                box: box,
                ink: ink,
                onPressed: _session.apply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A button of the draft options box: its [label] in the accent, pressed
/// with [ink] and the hover wash, focusable by the keyboard and pressed by
/// Enter or Space.
class DraftOptionsBoxButton extends StatelessWidget {
  /// A button saying [label].
  const DraftOptionsBoxButton({
    required this.label,
    required this.box,
    required this.ink,
    required this.onPressed,
    super.key,
  });

  /// What it says, from the chrome strings.
  final String label;

  /// The box's sizes.
  final DraftOptionsDesktopBox box;

  /// How it answers a press.
  final ChromeInkKind ink;

  /// What it does.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final radius = BorderRadius.circular(box.buttonRadius);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: DraftOptionsKeyFocus(
        onPressed: onPressed,
        borderRadius: radius,
        child: ChromeInk(
          kind: ink,
          color: ChromeButtonInks.pressOf(palette),
          hoverColor: ChromeButtonInks.hoverOf(palette),
          borderRadius: radius,
          onTap: onPressed,
          child: Container(
            height: box.buttonHeight,
            padding: EdgeInsets.symmetric(horizontal: box.buttonPadding),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              style: ChromeTypography.of(context).copyWith(
                color: palette.accent,
                fontSize: box.buttonFontSize,
                fontWeight: box.buttonWeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
