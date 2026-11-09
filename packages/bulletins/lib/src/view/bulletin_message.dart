import 'package:bulletins/src/bulletin/bulletin.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A bulletin's message as text, its [links] drawn in [linkColor] and
/// pressable, after an optional [prefix] (a title on the same text block).
///
/// Owns one tap recognizer per link: a span cannot dispose its own, so a
/// stateless text would leak one on every rebuild.
class BulletinMessage extends StatefulWidget {
  /// The [message] in [style] with [links] in [linkColor].
  const BulletinMessage({
    required this.message,
    required this.style,
    required this.linkColor,
    this.links = const [],
    this.prefix,
    this.maxLines,
    super.key,
  });

  /// The text.
  final String message;

  /// The ranges of [message] that are links.
  final List<BulletinLink> links;

  /// The text style.
  final TextStyle style;

  /// The colour of a link.
  final Color linkColor;

  /// What comes before [message] in the same text block; null for nothing.
  final InlineSpan? prefix;

  /// The most lines; null for no limit.
  final int? maxLines;

  @override
  State<BulletinMessage> createState() => _BulletinMessageState();
}

class _BulletinMessageState extends State<BulletinMessage> {
  List<TapGestureRecognizer> _$recognizers = const [];

  @override
  void initState() {
    super.initState();
    _$recognizers = _recognize(widget.links);
  }

  @override
  void didUpdateWidget(BulletinMessage old) {
    super.didUpdateWidget(old);
    if (!identical(old.links, widget.links)) {
      _dispose();
      _$recognizers = _recognize(widget.links);
    }
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  static List<TapGestureRecognizer> _recognize(List<BulletinLink> links) => [
    for (final link in links) TapGestureRecognizer()..onTap = link.onTap,
  ];

  void _dispose() {
    for (final recognizer in _$recognizers) {
      recognizer.dispose();
    }
  }

  List<InlineSpan> _spans() {
    final message = widget.message;
    final linkStyle = TextStyle(color: widget.linkColor);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final (i, link) in widget.links.indexed) {
      assert(
        link.start >= at && link.end <= message.length,
        'bulletin links are in order, apart, and inside the message',
      );
      final start = link.start.clamp(at, message.length);
      final end = link.end.clamp(start, message.length);
      if (start > at) spans.add(TextSpan(text: message.substring(at, start)));
      spans.add(
        TextSpan(
          text: message.substring(start, end),
          style: linkStyle,
          recognizer: _$recognizers[i],
          mouseCursor: SystemMouseCursors.click,
        ),
      );
      at = end;
    }
    if (at < message.length) spans.add(TextSpan(text: message.substring(at)));
    return spans;
  }

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(style: widget.style, children: [?widget.prefix, ..._spans()]),
    maxLines: widget.maxLines,
    overflow: TextOverflow.ellipsis,
  );
}
