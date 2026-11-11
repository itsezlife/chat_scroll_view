import 'dart:async';
import 'dart:math' as math;

import 'package:bulletins/src/bulletin/bulletin.dart';
import 'package:bulletins/src/controller/bulletin_controller.dart';
import 'package:bulletins/src/view/bulletin_builders.dart';
import 'package:bulletins/src/view/bulletin_message.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The Android bulletin card, as a set of `BulletinBuilders` for a host on
/// the Android policy.
///
/// [create] gives the whole set: the card in the undo background, or glass
/// tinted with it where the surface is a chat (glass is used only there);
/// the leading slot of each kind; the title over the message; and the Undo
/// or button in the accent. Sizes not owned by the policy (the slot boxes,
/// the text insets, the button paddings) are fixed here.
abstract final class BulletinBuilders$Android {
  // --- Metrics (in dp; the card is the drawn background) ---

  /// The leading box of the Lottie and simple layouts, from the card's start
  /// edge: 56 by 48 (the simple layout's 24 icon with 16 / 12 margins).
  static const double _slotWidth = 56;
  static const double _slotHeight = 48;

  /// A Lottie icon's size in its box; the
  /// copy and link icons use 36 and are drawn by a custom leading.
  static const double _animationSize = 32;

  /// The two-line layout's sticker or photo: 29 square at 12 from the start,
  /// 12 above and below; its text block starts at 54.
  static const double _thumbnailSize = 29;
  static const double _thumbnailInset = 12;
  static const double _thumbnailTextStart = 54;

  /// The undo countdown: 20 square at 21 from the start.
  static const double _countdownSize = 20;
  static const double _countdownStart = 21;

  /// The text's start without a leading, its end without a button (one line;
  /// under a title 8 + 4 of text padding), and its vertical padding.
  static const double _textStart = 16;
  static const double _textEnd = 16;
  static const double _titledTextEnd = 12;
  static const double _textVertical = 8;

  /// A button's measured width counts 12 less against the text, so
  /// the text's end inset reaches 12 into the button's box.
  static const double _buttonOverlap = 12;

  /// A message beside a custom button: 14, up to three lines.
  static const double _buttonMessageSize = 14;

  /// The weight Android chrome draws bold text at: the medium face (500).
  static const FontWeight _medium = FontWeight.w500;

  // --- The set ---

  /// The Android builders. [glass] draws the card as glass over the surface
  /// (a chat), otherwise it is the opaque undo background. [animation] and
  /// [thumbnail] resolve the opaque sources of those leading kinds (a Lottie
  /// from the asset cache, a sticker). A message's links are drawn in the
  /// accent.
  static BulletinBuilders create({
    bool glass = false,
    BulletinSourceBuilder? animation,
    BulletinSourceBuilder? thumbnail,
  }) => BulletinBuilders(
    frame: glass ? glassFrame : frame,
    content: (context, view) =>
        content(context, view, animation: animation, thumbnail: thumbnail),
    animation: animation,
    thumbnail: thumbnail,
  );

  // --- Frame ---

  /// The opaque card: the undo background (0xEA272F38 by default), the
  /// policy's radius and minimum height.
  static Widget frame(BuildContext context, BulletinView view, Widget child) =>
      BulletinBuilders.stockFrame(context, view, child);

  /// The card as glass, over a chat: the undo background over the blurred
  /// surface, at the glass's own opacity (0.76 frosted, 0.85 refracting,
  /// multiplied by the colour's alpha); no edge stroke and no shadow.
  ///
  /// The glass stack has no bulletin material, so the card borrows the
  /// floating-button material, whose 0.5 edge width is used as is, and
  /// recolours it in a nested theme scope. Adding a material to the
  /// foundation for one card would change every host's glass group.
  static Widget glassFrame(
    BuildContext context,
    BulletinView view,
    Widget child,
  ) {
    const none = Color(0x00000000);
    final glass = ChromeThemeScope.glassOf(context);
    return ChromeThemeScope(
      glass: glass.copyWith(
        panelButton: GlassMaterialColors(
          tint: view.tokens.background,
          strokeTop: none,
          strokeBottom: none,
          shadow: none,
        ),
      ),
      child: GlassSurface(
        material: GlassMaterial.panelButton,
        cornerRadius: view.policy.cornerRadius,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: view.policy.minHeight),
          child: child,
        ),
      ),
    );
  }

  // --- Content ---

  /// The leading slot, the title over the message, and the action, laid out
  /// in the Android card's arrangement.
  static Widget content(
    BuildContext context,
    BulletinView view, {
    BulletinSourceBuilder? animation,
    BulletinSourceBuilder? thumbnail,
  }) {
    final bulletin = view.bulletin;
    final policy = view.policy;
    final foreground = view.tokens.foreground;
    final title = bulletin.title;
    final action = bulletin.action;

    final messageSize = switch ((title, action)) {
      (_?, _) => policy.subtitleTextSize,
      (null, BulletinAction$Button()) => _buttonMessageSize,
      (null, _) => policy.messageTextSize,
    };
    // An undo message wraps to two lines, one beside a button to three; a
    // subtitle to two.
    final maxLines =
        bulletin.maxLines ??
        switch ((title, action)) {
          (_?, _) => 2,
          (null, BulletinAction$Undo()) => 2,
          (null, BulletinAction$Button()) => 3,
          (null, null) => 1,
        };
    final messageStyle = TextStyle(color: foreground, fontSize: messageSize);
    final text = ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _textVertical),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title case final title?)
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: policy.titleTextSize,
                  fontWeight: _medium,
                ),
              ),
            BulletinMessage(
              message: bulletin.message,
              links: bulletin.links,
              linkColor: view.tokens.accent,
              maxLines: maxLines,
              style: messageStyle,
            ),
          ],
        ),
      ),
    );

    final end = title == null ? _textEnd : _titledTextEnd;
    return Row(
      children: [
        _leading(context, view, animation: animation, thumbnail: thumbnail),
        Expanded(child: text),
        if (action == null)
          SizedBox(width: end)
        else ...[
          SizedBox(width: math.max(0, end - _buttonOverlap)),
          _ActionButton$Android(view: view),
        ],
      ],
    );
  }

  static Widget _leading(
    BuildContext context,
    BulletinView view, {
    required BulletinSourceBuilder? animation,
    required BulletinSourceBuilder? thumbnail,
  }) {
    Widget slot(Widget? child) => SizedBox(
      width: _slotWidth,
      height: _slotHeight,
      child: Center(child: child),
    );
    return switch (view.bulletin.leading) {
      null => const SizedBox(width: _textStart),
      BulletinLeading$Icon(:final icon) => slot(
        ChromeIcon(
          icon,
          size: view.policy.iconSize,
          color: view.tokens.foreground,
        ),
      ),
      BulletinLeading$Animation(:final source) => slot(
        SizedBox.square(
          dimension: _animationSize,
          child: animation?.call(context, source, view),
        ),
      ),
      BulletinLeading$Thumbnail(:final source) => Padding(
        padding: const EdgeInsetsDirectional.only(
          start: _thumbnailInset,
          top: _thumbnailInset,
          bottom: _thumbnailInset,
          end: _thumbnailTextStart - _thumbnailInset - _thumbnailSize,
        ),
        child: SizedBox.square(
          dimension: _thumbnailSize,
          child: thumbnail?.call(context, source, view),
        ),
      ),
      BulletinLeading$Countdown() => SizedBox(
        width: _slotWidth,
        height: _slotHeight,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: _countdownStart),
            child: BulletinCountdown$Android(
              handle: view.handle,
              color: view.tokens.countdown,
            ),
          ),
        ),
      ),
      BulletinLeading$Custom(:final builder) => slot(builder(context)),
    };
  }
}

// --- Action ---

/// The undo button with text: the label 14 medium
/// in the accent, padded 12 / 8 inside a box 8 from its neighbours, pressed
/// with the chrome ink in the accent at 0x19 inside a 6 radius (the
/// ripple's colour and mask). A custom button is the same with its own
/// label.
///
/// The ink takes the pointer at once on its down, so the press shows while
/// the card's horizontal drag still competes for it.
class _ActionButton$Android extends StatelessWidget {
  const _ActionButton$Android({required this.view});

  final BulletinView view;

  @override
  Widget build(BuildContext context) {
    final label = switch (view.bulletin.action) {
      BulletinAction$Undo() => view.strings.undoAction,
      BulletinAction$Button(:final label) => label,
      null => '',
    };
    final accent = view.tokens.accent;
    return Semantics(
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ChromeInk(
          color: accent.withAlpha(0x19),
          hoverColor: accent.withAlpha(0x0F),
          borderRadius: BorderRadius.circular(6),
          onTap: view.handle.pressAction,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 14,
                fontWeight: BulletinBuilders$Android._medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Countdown ---

/// The undo countdown: a 20 ring, 2 wide with
/// round caps, inset by 1, that empties counter-clockwise from the top over
/// the time left, with the whole seconds left in 12 digits inside. When the
/// second changes the old digit slides 10 down and fades while the new one
/// slides in from 10 above, over about 150 ms (16/150 of the way per
/// frame).
///
/// Reads the handle's remaining time every frame while mounted. Draws
/// nothing for a bulletin without a timeout.
class BulletinCountdown$Android extends StatefulWidget {
  /// The countdown of [handle] in [color].
  const BulletinCountdown$Android({
    required this.handle,
    required this.color,
    super.key,
  });

  /// The bulletin counted down.
  final BulletinHandle handle;

  /// The ring and digit colour (the info colour).
  final Color color;

  /// How long a digit change takes.
  static const Duration digitChange = Duration(milliseconds: 150);

  /// How far a changing digit slides.
  static const double digitSlide = 10;

  @override
  State<BulletinCountdown$Android> createState() =>
      _BulletinCountdown$AndroidState();
}

class _BulletinCountdown$AndroidState extends State<BulletinCountdown$Android>
    with SingleTickerProviderStateMixin {
  late final Ticker _$ticker;
  Duration _$now = Duration.zero;
  int? _$seconds;
  int? _$previous;
  Duration _$changedAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _$ticker = createTicker((elapsed) => setState(() => _$now = elapsed));
    unawaited(_$ticker.start());
  }

  @override
  void dispose() {
    _$ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.handle;
    final (timeout, remaining) = (handle.timeout, handle.remaining);
    if (timeout == null || remaining == null) return const SizedBox.shrink();
    final seconds = math.max(0, (remaining.inMilliseconds / 1000).ceil());
    if (seconds != _$seconds) {
      // The first value appears without a change: there is no outgoing layout
      // on the first frame.
      _$previous = _$seconds;
      _$seconds = seconds;
      _$changedAt = _$now;
    }
    final instant = ChromeMotionScope.of(context).speed.isInstant;
    final progress = instant
        ? 1.0
        : ((_$now - _$changedAt).inMicroseconds /
                  BulletinCountdown$Android.digitChange.inMicroseconds)
              .clamp(0.0, 1.0);
    final fraction = remaining.inMicroseconds / timeout.inMicroseconds;
    final style = TextStyle(
      color: widget.color,
      fontSize: 12,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1,
    );
    const slide = BulletinCountdown$Android.digitSlide;
    Widget digit(int value, double opacity, double dy) => Transform.translate(
      // The digits lift by half a point.
      offset: Offset(0, dy - 0.5),
      child: Opacity(
        opacity: opacity,
        child: Text('$value', style: style),
      ),
    );
    return SizedBox.square(
      dimension: BulletinBuilders$Android._countdownSize,
      child: CustomPaint(
        painter: _RingPainter(fraction: fraction, color: widget.color),
        child: Stack(
          alignment: Alignment.center,
          children: switch (_$previous) {
            final previous? when progress < 1 => [
              digit(previous, 1 - progress, slide * progress),
              digit(seconds, progress, -slide * (1 - progress)),
            ],
            _ => [digit(seconds, 1, 0)],
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rect = (Offset.zero & size).deflate(1);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      -2 * math.pi * fraction.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}
