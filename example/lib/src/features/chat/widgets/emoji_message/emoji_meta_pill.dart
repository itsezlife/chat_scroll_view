import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatMessageTapBarrier;
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_glyphs.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_service_colors.dart';
import 'package:flutter/widgets.dart';

/// The time string of the pill: `09:05`, or `edited 09:05` for an edited
/// message. The edited mark is not a separate element on any platform: it is
/// part of the one string, so it counts in the pill's width.
String emojiMetaTime(DateTime createdAt, {required bool edited}) => edited
    ? 'edited ${DemoMessageMeta.formatTime(createdAt)}'
    : DemoMessageMeta.formatTime(createdAt);

/// The compact count of views: `999`, `1.2K`, `3.4M`.
String emojiViewsLabel(int views) {
  String compact(double value, String suffix) {
    final text = value.toStringAsFixed(1);
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}$suffix';
  }

  if (views >= 1000000) return compact(views / 1000000, 'M');
  if (views >= 1000) return compact(views / 1000, 'K');
  return '$views';
}

/// The text style of the pill under [chrome], in [color].
TextStyle emojiMetaStyle(EmojiChrome chrome, Color color) => TextStyle(
  color: color,
  fontSize: chrome.metaFontSize,
  height: 1.17,
  fontWeight: FontWeight.w400,
  decoration: TextDecoration.none,
);

/// Measures one line of [text] in [style], ceiled as the reference ceils its
/// time width.
Size measureEmojiLine(String text, TextStyle style, TextDirection direction) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textScaler: TextScaler.noScaling,
    maxLines: 1,
  )..layout();
  final size = Size(painter.width.ceilToDouble(), painter.height);
  painter.dispose();
  return size;
}

/// The measured text of a pill.
EmojiMetaMetrics measureEmojiMeta({
  required EmojiChrome chrome,
  required String time,
  required int? views,
  required TextDirection direction,
}) {
  final style = emojiMetaStyle(chrome, const Color(0xFFFFFFFF));
  final timeSize = measureEmojiLine(time, style, direction);
  return EmojiMetaMetrics(
    timeWidth: timeSize.width,
    timeHeight: timeSize.height,
    viewsWidth: views == null
        ? null
        : measureEmojiLine(emojiViewsLabel(views), style, direction).width,
  );
}

/// The pill: a translucent service-coloured shape holding the views, the time
/// and the delivery state, laid out by [layout] (the platform's).
///
/// A mouse click on it is not a message tap ([ChatMessageTapBarrier]): the
/// pill is the status of the message, not the message. Desktop reveals it on
/// hover, so the pointer that reveals it is the one most likely to press it.
class EmojiMetaPill extends StatelessWidget {
  /// Draws [time] (and [views]) in a pill shaped by [layout].
  const EmojiMetaPill({
    required this.chrome,
    required this.layout,
    required this.colors,
    required this.time,
    this.views,
    super.key,
  });

  /// The platform's chrome.
  final EmojiChrome chrome;

  /// Where the parts of the pill are.
  final EmojiPillLayout layout;

  /// The service colours.
  final EmojiServiceColors colors;

  /// The time string.
  final String time;

  /// The views count, or null.
  final int? views;

  @override
  Widget build(BuildContext context) {
    final style = emojiMetaStyle(chrome, colors.text);
    final size = layout.size;
    final status = layout.status;
    final icon = layout.viewsIcon;
    final count = layout.viewsCountOrigin;
    return ChatMessageTapBarrier(
      child: SizedBox.fromSize(
        size: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.pill,
            borderRadius: BorderRadius.circular(chrome.pillRadius(size.height)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              if (icon != null)
                Positioned.fromRect(
                  rect: icon,
                  child: CustomPaint(
                    painter: EmojiViewsIconPainter(color: colors.text),
                  ),
                ),
              if (count != null && views != null)
                Positioned(
                  left: count.dx,
                  top: count.dy,
                  child: Text(
                    emojiViewsLabel(views!),
                    style: style,
                    maxLines: 1,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              Positioned(
                left: layout.timeOrigin.dx,
                top: layout.timeOrigin.dy,
                child: Text(
                  time,
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                ),
              ),
              if (status != null)
                Positioned.fromRect(
                  rect: status,
                  child: CustomPaint(
                    painter: EmojiTicksPainter(
                      state: layout.state,
                      color: colors.text,
                      vector: chrome.usesVectorTicks,
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
