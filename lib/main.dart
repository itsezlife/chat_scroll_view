import 'dart:async';
import 'dart:ui' as ui;

import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:l/l.dart';

void main() => runZonedGuarded<void>(
  () => runApp(const App()),
  (error, stackTrace) => l.e('Top level exception: $error'),
);

/// {@template app}
/// App widget.
/// {@endtemplate}
class App extends StatelessWidget {
  /// {@macro app}
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chat Scroll View',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
    ),
    home: const ChatScreen(),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final _DemoController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _DemoController();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chat Scroll View')),
    body: SafeArea(
      child: ChatScrollView(
        controller: _controller,
        builder: _DemoMessageRender.new,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Demo controller with 256 hardcoded messages
// ---------------------------------------------------------------------------

class _DemoController extends ChatScrollController {
  static const int _messageCount = 256;

  void init() {
    final now = DateTime.now();
    final messages = <IChatMessage>[];
    for (var i = 0; i < _messageCount; i++) {
      final time = now.subtract(Duration(minutes: _messageCount - i));
      messages.add(
        ChatMessage$User(
          id: i,
          createdAt: time,
          updatedAt: time,
          content: 'Message #$i — '
              'The first rule of Fight Club is: you do not talk about Fight Club. '
              'The second rule of Fight Club is: you DO NOT talk about Fight Club!',
        ),
      );
    }
    upsertMessages(messages);
    oldestKnownId = 0;
    newestKnownId = _messageCount - 1;
    reachedOldest = true;
    reachedNewest = true;
    // Anchor to the newest message, positioned at bottom of viewport.
    // A large offset pushes it down; boundary clamping will correct it.
    jumpTo(_messageCount - 1);
  }

  @override
  Future<List<IChatMessage>> fetch({int? from, int? to, DateTime? after}) async {
    // All data is already loaded — nothing to fetch.
    return const [];
  }
}

// ---------------------------------------------------------------------------
// Demo message render — simple bubble with text
// ---------------------------------------------------------------------------

class _DemoMessageRender extends ChatMessageRender {
  _DemoMessageRender(IChatMessage? message) {
    if (message != null) _updateText(message);
  }

  static const double _padding = 12.0;
  static const double _bubblePadding = 16.0;
  static const double _bubbleRadius = 12.0;

  IChatMessage? _message;
  ui.Paragraph? _paragraph;

  void _updateText(IChatMessage message) {
    _message = message;
    dirty = true;
  }

  @override
  void update(IChatMessage? message, ChatMessageStatus status) {
    if (identical(_message, message)) return;
    if (message == null) {
      _message = null;
      _paragraph = null;
      dirty = true;
      return;
    }
    _updateText(message);
  }

  @override
  double performLayout(double availableWidth) {
    final message = _message;
    if (message == null) return 0.0;

    final content = switch (message) {
      ChatMessage$User(:final content) => content,
      ChatMessage$System(:final content) => content,
      _ => 'Message #${message.id}',
    };

    final textWidth = availableWidth - _bubblePadding * 2 - _padding * 2;
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: 15.0,
        fontFamily: '.AppleSystemUIFont',
        height: 1.4,
      ),
    )
      ..pushStyle(ui.TextStyle(color: const Color(0xFF1A1A1A)))
      ..addText(content)
      ..pop();

    _paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: textWidth));

    return _paragraph!.height + _bubblePadding * 2 + _padding;
  }

  @override
  void paintMessage(Canvas canvas, Size size) {
    final paragraph = _paragraph;
    if (paragraph == null) return;

    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _padding,
        _padding / 2,
        size.width - _padding * 2,
        size.height - _padding,
      ),
      const Radius.circular(_bubbleRadius),
    );

    // Alternate bubble color by message ID.
    final isEven = (_message?.id ?? 0).isEven;
    final bgColor = isEven
        ? const Color(0xFFE3F2FD)
        : const Color(0xFFF5F5F5);

    canvas.drawRRect(bubbleRect, Paint()..color = bgColor);
    canvas.save();
    canvas.translate(_padding + _bubblePadding, _padding / 2 + _bubblePadding);
    canvas.drawParagraph(paragraph, Offset.zero);
    canvas.restore();
  }

  @override
  void dispose() {
    _paragraph = null;
    super.dispose();
  }
}
