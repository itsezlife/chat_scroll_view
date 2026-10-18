import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_meta_pill.dart'
    show measureEmojiLine;
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_service_colors.dart';
import 'package:flutter/widgets.dart';

/// What a header says: a reply's sender and quoted line, a forward's source,
/// or both.
@immutable
final class EmojiHeaderData {
  /// A header of a [replySender] and [replyText], and/or a [forwardedFrom].
  const EmojiHeaderData({this.replySender, this.replyText, this.forwardedFrom})
    : assert(
        (replySender != null && replyText != null) || forwardedFrom != null,
        'A header is a reply, a forward or both.',
      );

  /// A reply to [sender] quoting [text].
  const EmojiHeaderData.reply({required String sender, required String text})
    : this(replySender: sender, replyText: text);

  /// A forward from [source].
  const EmojiHeaderData.forward(String source) : this(forwardedFrom: source);

  /// Who wrote the quoted message, or null.
  final String? replySender;

  /// One line of the quoted message.
  final String? replyText;

  /// Where the message was forwarded from, or null.
  final String? forwardedFrom;

  /// Which of the three headers this is.
  EmojiHeaderShape get shape => switch ((replySender, forwardedFrom)) {
    (_?, _?) => EmojiHeaderShape.forwardedReply,
    (_?, null) => EmojiHeaderShape.reply,
    _ => EmojiHeaderShape.forward,
  };

  /// The first of the forward's two lines.
  static const String forwardedLabel = 'Forwarded from';
}

/// A header measured for a chrome: its panel's size and the widths its lines
/// are set at.
@immutable
final class EmojiHeaderMeasure {
  const EmojiHeaderMeasure._(this.data, this.text, this.size);

  /// Measures [data] under [chrome]; no line is wider than [maxLine].
  factory EmojiHeaderMeasure.of(
    EmojiHeaderData data,
    EmojiChrome chrome, {
    required double maxLine,
    required TextDirection direction,
  }) {
    final name = _nameStyle(chrome, const Color(0xFFFFFFFF));
    final plain = _textStyle(chrome, const Color(0xFFFFFFFF));
    double line(String? text, TextStyle style) => text == null
        ? 0
        : measureEmojiLine(text, style, direction).width.clamp(0, maxLine);
    final nameHeight = measureEmojiLine('Ag', name, direction).height;
    final textHeight = measureEmojiLine('Ag', plain, direction).height;
    final fwd = data.forwardedFrom == null
        ? 0.0
        : [
            line(EmojiHeaderData.forwardedLabel, plain),
            line(data.forwardedFrom, name),
          ].reduce((a, b) => a > b ? a : b);
    final text = EmojiHeaderText(
      nameWidth: line(data.replySender, name),
      nameHeight: nameHeight,
      textWidth: line(data.replyText, plain),
      textHeight: textHeight,
      forwardWidth: fwd,
      forwardHeight: data.forwardedFrom == null ? 0 : nameHeight + textHeight,
    );
    return EmojiHeaderMeasure._(
      data,
      text,
      chrome.headerSize(shape: data.shape, text: text),
    );
  }

  /// What the header says.
  final EmojiHeaderData data;

  /// The measured lines.
  final EmojiHeaderText text;

  /// The panel's size.
  final Size size;
}

TextStyle _nameStyle(EmojiChrome chrome, Color color) => TextStyle(
  color: color,
  fontSize: chrome.headerFontSize,
  height: 1.2,
  fontWeight: chrome is EmojiChrome$Android ? FontWeight.w700 : FontWeight.w600,
  decoration: TextDecoration.none,
);

TextStyle _textStyle(EmojiChrome chrome, Color color) => TextStyle(
  color: color,
  fontSize: chrome.headerFontSize,
  height: 1.2,
  fontWeight: FontWeight.w400,
  decoration: TextDecoration.none,
);

/// A reply or forward header in the service-panel style of a message without a
/// bubble: white lines on the service colour, a 3-wide bar before a reply, the
/// platform's radius and fonts, in the size [measure] gives.
class EmojiHeaderPanel extends StatelessWidget {
  /// Draws [measure] under [chrome].
  const EmojiHeaderPanel({
    required this.chrome,
    required this.colors,
    required this.measure,
    super.key,
  });

  /// The platform's chrome.
  final EmojiChrome chrome;

  /// The service colours.
  final EmojiServiceColors colors;

  /// The header and its size.
  final EmojiHeaderMeasure measure;

  // Where a platform puts the lines inside the panel (research 04, 1.6, 2.5,
  // 3.4): the forward block's origin and height, then the reply's offsets in
  // its own block.
  ({Offset forward, double forwardHeight, Offset name, Offset text, double bar})
  _inner(EmojiHeaderShape shape) {
    final hasForward = shape != EmojiHeaderShape.reply;
    final both = shape == EmojiHeaderShape.forwardedReply;
    final t = measure.text;
    return switch (chrome) {
      EmojiChrome$Android() => (
        forward: const Offset(7, 6),
        forwardHeight: 44,
        name: Offset(11, hasForward && both ? 44 + 1.7 : 4),
        text: Offset(11, hasForward && both ? 44 + 19.7 : 22),
        bar: both ? 44 : 0,
      ),
      EmojiChrome$Ios() => (
        forward: const Offset(7, 6),
        forwardHeight: EmojiChrome$Ios.unverifiedForwardHeight,
        name: Offset(
          11,
          (both ? EmojiChrome$Ios.unverifiedForwardHeight : 0) + 3,
        ),
        text: Offset(
          11,
          (both ? EmojiChrome$Ios.unverifiedForwardHeight : 0) +
              3 +
              t.nameHeight,
        ),
        bar: both ? EmojiChrome$Ios.unverifiedForwardHeight : 0,
      ),
      EmojiChrome$Desktop() => (
        forward: const Offset(6, 6),
        forwardHeight: 6 + t.forwardHeight + 6,
        name: Offset(11, (both ? 6 + t.forwardHeight + 6 : 0) + 2),
        text: Offset(
          11,
          (both ? 6 + t.forwardHeight + 6 : 0) + 2 + t.nameHeight,
        ),
        bar: both ? 6 + t.forwardHeight + 6 : 0,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final data = measure.data;
    final shape = data.shape;
    final inner = _inner(shape);
    final size = measure.size;
    final name = _nameStyle(chrome, colors.text);
    final plain = _textStyle(chrome, colors.text);
    final isReply = shape != EmojiHeaderShape.forward;
    Widget line(String text, TextStyle style, double width) => SizedBox(
      width: width,
      child: Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        textScaler: TextScaler.noScaling,
      ),
    );

    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(chrome.headerRadius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(chrome.headerRadius),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              if (data.forwardedFrom != null) ...<Widget>[
                Positioned(
                  left: inner.forward.dx,
                  top: inner.forward.dy,
                  child: line(
                    EmojiHeaderData.forwardedLabel,
                    plain,
                    measure.text.forwardWidth,
                  ),
                ),
                Positioned(
                  left: inner.forward.dx,
                  top: inner.forward.dy + measure.text.textHeight,
                  child: line(
                    data.forwardedFrom!,
                    name,
                    measure.text.forwardWidth,
                  ),
                ),
              ],
              if (isReply) ...<Widget>[
                Positioned(
                  left: 0,
                  top: inner.bar,
                  width: 3,
                  height: size.height - inner.bar,
                  child: ColoredBox(color: colors.text),
                ),
                Positioned(
                  left: inner.name.dx,
                  top: inner.name.dy,
                  child: line(data.replySender!, name, measure.text.nameWidth),
                ),
                Positioned(
                  left: inner.text.dx,
                  top: inner.text.dy,
                  child: line(data.replyText!, plain, measure.text.textWidth),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
