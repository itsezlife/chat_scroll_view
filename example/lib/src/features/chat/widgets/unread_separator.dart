import 'package:flutter/material.dart';

/// Unread-messages bar for the demo chat, built by
/// `ChatScrollView.unreadSeparatorBuilder` above the first unread incoming
/// message.
///
/// A fixed 40 px cell: a full-width strip below a small top gap, a centered
/// label on top of it, and a down arrow at the strip's right edge.
/// The label is one line at a fixed logical size that ignores the ambient
/// text scale and text style, so no font scale, width, or ambient theme can
/// grow the row or shift the label. A label wider than the cell ends in an
/// ellipsis.
///
/// Colors come from [UnreadSeparatorColors] on the ambient [ThemeData].
class UnreadSeparator extends StatelessWidget {
  /// Builds the bar. The label carries no count.
  const UnreadSeparator({super.key});

  /// Row-chrome extent the viewport stacks between the date separator and
  /// the message body.
  static const double _cellHeight = 40;

  /// Gap between the cell top and the strip.
  static const double _stripTop = 7;

  /// Strip extent: [_stripFillHeight] of fill plus a [_stripShadeHeight]
  /// shade line along its bottom edge.
  static const double _stripHeight = _stripFillHeight + _stripShadeHeight;
  static const double _stripFillHeight = 26;
  static const double _stripShadeHeight = 1;

  /// Untinted strip fill: white at 245/255 alpha.
  static const Color _stripFillSource = Color(0xF5FFFFFF);

  /// Untinted shade line: rgb(12, 32, 44) at 20/255 alpha.
  static const Color _stripShadeSource = Color(0x140C202C);

  /// Horizontal inset of the label box from each cell edge.
  static const double _labelSideMargin = 32;

  /// Bottom padding of the label box; the box centers in the cell, so the
  /// line sits half of this above the cell center.
  static const double _labelBottomPadding = 1;

  static const double _labelFontSize = 14;

  static const double _arrowIconSize = 24;

  /// Top padding of the arrow box; the padded box centers in the strip.
  static const double _arrowTopPadding = 2;

  /// Gap between the arrow box and the strip's right edge. The chevron glyph
  /// ends 6 inside its box, so the glyph itself sits 10 from the edge.
  static const double _arrowRightMargin = 4;

  @override
  Widget build(BuildContext context) {
    final colors = UnreadSeparatorColors.of(context);
    final ambient = DefaultTextStyle.of(context).style;
    return SizedBox(
      height: _cellHeight,
      width: double.infinity,
      child: Stack(
        children: <Widget>[
          Positioned(
            top: _stripTop,
            left: 0,
            right: 0,
            height: _stripHeight,
            child: Stack(
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      height: _stripFillHeight,
                      child: ColoredBox(
                        color: _multiply(_stripFillSource, colors.background),
                      ),
                    ),
                    SizedBox(
                      height: _stripShadeHeight,
                      child: ColoredBox(
                        color: _multiply(_stripShadeSource, colors.background),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: _arrowTopPadding,
                      right: _arrowRightMargin,
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: _arrowIconSize,
                      color: colors.arrow,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                _labelSideMargin,
                0,
                _labelSideMargin,
                _labelBottomPadding,
              ),
              child: Center(
                child: Text(
                  'Непрочитанные сообщения',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    inherit: false,
                    fontFamily: ambient.fontFamily,
                    fontFamilyFallback: ambient.fontFamilyFallback,
                    fontSize: _labelFontSize,
                    fontWeight: FontWeight.w500,
                    color: colors.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Multiplies every channel of [source], alpha included, by [tint] — how
/// [UnreadSeparatorColors.background] tints the strip.
Color _multiply(Color source, Color tint) => Color.from(
  alpha: source.a * tint.a,
  red: source.r * tint.r,
  green: source.g * tint.g,
  blue: source.b * tint.b,
);

/// Color roles of [UnreadSeparator], one per `chat_unreadMessagesStart*`
/// theme key.
///
/// Register [light] or [dark] in [ThemeData.extensions] next to the palette it
/// belongs to. Without a registered extension, [of] picks the palette from
/// [ThemeData.brightness].
@immutable
class UnreadSeparatorColors extends ThemeExtension<UnreadSeparatorColors> {
  /// Creates the bar's color roles.
  const UnreadSeparatorColors({
    required this.background,
    required this.text,
    required this.arrow,
  });

  /// Light palette (default theme colors).
  static const light = UnreadSeparatorColors(
    background: Color(0xFFFFFFFF),
    text: Color(0xFF5695CC),
    arrow: Color(0xFFA2B5C7),
  );

  /// Dark palette (night theme colors).
  static const dark = UnreadSeparatorColors(
    background: Color(0xFF212122),
    text: Color(0xDAFFFFFF),
    arrow: Color(0xFF6D6D6F),
  );

  /// The extension on the ambient [ThemeData], or the palette matching its
  /// brightness.
  static UnreadSeparatorColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<UnreadSeparatorColors>() ??
        switch (theme.brightness) {
          Brightness.light => light,
          Brightness.dark => dark,
        };
  }

  /// Strip tint (`chat_unreadMessagesStartBackground`).
  ///
  /// A tint, not a fill: the painted fill is this color at 245/255 of its
  /// alpha, and the bottom shade line is a darkened copy at 20/255, so the
  /// strip stays slightly translucent over the wallpaper.
  final Color background;

  /// Label color (`chat_unreadMessagesStartText`).
  final Color text;

  /// Arrow icon color (`chat_unreadMessagesStartArrowIcon`).
  final Color arrow;

  @override
  UnreadSeparatorColors copyWith({
    Color? background,
    Color? text,
    Color? arrow,
  }) => UnreadSeparatorColors(
    background: background ?? this.background,
    text: text ?? this.text,
    arrow: arrow ?? this.arrow,
  );

  @override
  UnreadSeparatorColors lerp(covariant UnreadSeparatorColors? other, double t) {
    if (other == null) return this;
    return UnreadSeparatorColors(
      background: Color.lerp(background, other.background, t)!,
      text: Color.lerp(text, other.text, t)!,
      arrow: Color.lerp(arrow, other.arrow, t)!,
    );
  }
}
