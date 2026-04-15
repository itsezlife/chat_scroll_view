import 'dart:async';
import 'dart:ui' as ui;

import 'package:chatscrollview/src/comments_data_source.dart';
import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_message_render.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_scroll/chat_selection_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_shimmer_render.dart';
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
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    ),
    debugShowCheckedModeBanner: false,
    showPerformanceOverlay: false,
    home: const ChatScreen(),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatDataSource? _dataSource;
  late final ChatScrollController _scrollController;
  late final ChatSelectionController _selectionController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ChatScrollController();
    _selectionController = ChatSelectionController();
    _initDataSource();
  }

  Future<void> _initDataSource() async {
    try {
      final comments = await CommentsDataSource.load();
      final count = comments.manifest.totalMessages;
      _dataSource = comments;
      _scrollController.oldestKnownId = 0;
      _scrollController.newestKnownId = count - 1;
      _scrollController.reachedOldest = true;
      _scrollController.reachedNewest = true;
      _scrollController.jumpTo(count - 1);
    } on Object catch (e) {
      l.w('CommentsDataSource failed, falling back to demo: $e');
      const messageCount = 4000;
      _dataSource = _DemoDataSource(messageCount: messageCount);
      _scrollController.oldestKnownId = 0;
      _scrollController.newestKnownId = messageCount - 1;
      _scrollController.reachedOldest = true;
      _scrollController.reachedNewest = true;
      _scrollController.jumpTo(messageCount - 1);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _dataSource == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat Scroll View')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      /* appBar: AppBar(title: const Text('Chat Scroll View')), */
      body: SafeArea(
        child: ChatScrollView(
          dataSource: _dataSource!,
          controller: _scrollController,
          selectionController: _selectionController,
          shimmer: _DemoShimmerRender(),
          builder: _DemoMessageRender.new,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Demo data source — generates messages on demand via async fetch
// ---------------------------------------------------------------------------

class _DemoDataSource extends ChatDataSource {
  _DemoDataSource({required this.messageCount});

  final int messageCount;
  final DateTime _baseTime = DateTime.now();

  @override
  Future<List<IChatMessage>> fetch({
    int? from,
    int? to,
    DateTime? after,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final lo = (from ?? 0).clamp(0, messageCount - 1);
    final hi = (to ?? messageCount - 1).clamp(0, messageCount - 1);
    return <IChatMessage>[
      for (var i = lo; i <= hi; i++)
        ChatMessage$User(
          id: i,
          sender: 'User',
          createdAt: _baseTime.subtract(Duration(minutes: messageCount - i)),
          updatedAt: _baseTime.subtract(Duration(minutes: messageCount - i)),
          content:
              'Message #$i — '
              'The first rule of Fight Club is: '
              'you do not talk about Fight Club. '
              'The second rule of Fight Club is: '
              'you DO NOT talk about Fight Club!',
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Demo shimmer render
// ---------------------------------------------------------------------------

class _DemoShimmerRender extends ChatShimmerRender {
  static const double _padding = 12.0;
  static const double _bubblePadding = 16.0;
  static const double _bubbleRadius = 12.0;
  static const double _height = 72.0;

  @override
  double performLayout(double availableWidth) => _height;

  @override
  void paint(Canvas canvas, Size size) {
    final bubbleWidth = size.width - _padding * 2;
    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        _padding,
        _padding / 2,
        bubbleWidth,
        size.height - _padding,
      ),
      const Radius.circular(_bubbleRadius),
    );
    canvas.drawRRect(bubbleRect, Paint()..color = const Color(0xFF2C2C2C));

    final linePaint = Paint()..color = const Color(0xFF424242);
    final lineTop = _padding / 2 + _bubblePadding;
    for (var i = 0; i < 2; i++) {
      final y = lineTop + i * 20.0;
      final w = i == 1 ? bubbleWidth * 0.5 : bubbleWidth * 0.75;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(_padding + _bubblePadding, y, w, 10),
          const Radius.circular(4),
        ),
        linePaint,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Sender color palette — deterministic color per username
// ---------------------------------------------------------------------------

const _senderColors = <Color>[
  Color(0xFF42A5F5), // blue
  Color(0xFF66BB6A), // green
  Color(0xFFEF5350), // red
  Color(0xFFAB47BC), // purple
  Color(0xFFFF7043), // deep orange
  Color(0xFF26C6DA), // cyan
  Color(0xFFFFCA28), // amber
  Color(0xFFEC407A), // pink
  Color(0xFF8D6E63), // brown
  Color(0xFF78909C), // blue grey
];

Color _colorForSender(String sender) =>
    _senderColors[sender.hashCode.abs() % _senderColors.length];

// ---------------------------------------------------------------------------
// Demo message render — bubble with sender name and text
// ---------------------------------------------------------------------------

class _DemoMessageRender extends ChatMessageRender {
  _DemoMessageRender(IChatMessage? message) {
    if (message is IChatMessage) _updateText(message);
  }

  static const double _padding = 12.0;
  static const double _bubblePadding = 16.0;
  static const double _bubbleRadius = 12.0;
  static const double _indicatorSpace = 40.0;
  static const double _senderHeight = 20.0;

  IChatMessage? _message;
  ui.Paragraph? _paragraph;
  ui.Paragraph? _senderParagraph;
  double _layoutWidth = 0;

  static const Set<String> _teamMembers = {
    'Hixie',
    'justinmc',
    'jonahwilliams',
    'chunhtai',
    'tvolkert',
    'goderbauer',
    'zanderso',
    'liyuqian',
    'aam',
    'gspencergoog',
    'mit-mit',
    'xster',
    'AlexV525',
    'maheshj01',
    'darshankawar',
    'gaaclarke',
    'knopp',
    'mraleph',
    'jmagman',
    'danagbemava-nc',
    'huycozy',
    'slightfoot',
    'guidezpl',
    'pedromassango',
    'abarth',
    'gnprice',
    'cbracken',
    'exaby73',
    'loic-sharma',
    'nt4f04uNd',
    'jason-simmons',
    'ColdPaleLight',
  };

  void _updateText(IChatMessage message) {
    _message = message;
    alignment = _teamMembers.contains(message.sender)
        ? ChatMessageAlignment.right
        : ChatMessageAlignment.left;
    dirty = true;
  }

  @override
  void update(IChatMessage? message, ChatMessageStatus status) {
    if (identical(_message, message)) return;
    if (message is! IChatMessage) {
      _message = null;
      _paragraph = null;
      _senderParagraph = null;
      dirty = true;
      return;
    }
    _updateText(message);
  }

  @override
  double performLayout(double availableWidth) {
    final message = _message;
    if (message == null) return 0.0;

    _layoutWidth = availableWidth;

    final content = switch (message) {
      ChatMessage$User(:final content) => content,
      ChatMessage$System(:final content) => content,
      _ => 'Message #${message.id}',
    };

    final textWidth = availableWidth - _bubblePadding * 2 - _padding * 2;

    // Build sender label.
    final senderColor = _colorForSender(message.sender);
    final senderBuilder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: 13.0,
              fontFamily: '.AppleSystemUIFont',
              fontWeight: FontWeight.w600,
            ),
          )
          ..pushStyle(ui.TextStyle(color: senderColor))
          ..addText(message.sender)
          ..pop();
    _senderParagraph = senderBuilder.build()
      ..layout(ui.ParagraphConstraints(width: textWidth));

    // Build content text.
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: 15.0,
              fontFamily: '.AppleSystemUIFont',
              height: 1.4,
            ),
          )
          ..pushStyle(ui.TextStyle(color: const Color(0xFFE0E0E0)))
          ..addText(content)
          ..pop();

    _paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: textWidth));

    return _senderHeight + _paragraph!.height + _bubblePadding * 2 + _padding;
  }

  @override
  void paintMessage(Canvas canvas, Size size) {
    final paragraph = _paragraph;
    if (paragraph == null) return;

    final bubbleWidth = _layoutWidth - _padding * 2;
    final bubbleLeft = switch (alignment) {
      ChatMessageAlignment.left =>
        _padding + (selectionMode ? _indicatorSpace : 0),
      ChatMessageAlignment.right => size.width - bubbleWidth - _padding,
    };

    final bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        bubbleLeft,
        _padding / 2,
        bubbleWidth,
        size.height - _padding,
      ),
      const Radius.circular(_bubbleRadius),
    );

    // Team members get a distinct bubble color.
    final isTeam = _teamMembers.contains(_message?.sender);
    final bgColor = isTeam ? const Color(0xFF1A237E) : const Color(0xFF2C2C2C);

    canvas.drawRRect(bubbleRect, Paint()..color = bgColor);
    if (selected) {
      canvas.drawRRect(bubbleRect, Paint()..color = const Color(0x4042A5F5));
    }

    canvas.save();
    canvas.translate(
      bubbleLeft + _bubblePadding,
      _padding / 2 + _bubblePadding,
    );

    // Draw sender name.
    if (_senderParagraph != null) {
      canvas.drawParagraph(_senderParagraph!, Offset.zero);
    }

    // Draw content below sender.
    canvas.translate(0, _senderHeight);
    canvas.drawParagraph(paragraph, Offset.zero);
    canvas.restore();
  }

  @override
  void dispose() {
    _paragraph = null;
    _senderParagraph = null;
    super.dispose();
  }
}
