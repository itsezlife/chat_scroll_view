import 'package:catalog_assets/catalog_assets.dart' show InlineEmbedResolver;
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_markdown_autoscroll.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_markdown_body.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';

/// Asks for [onFrame] to run once, on the next frame.
///
/// The seam [ChatStreamingBodyController] coalesces on, so a test drives the
/// frames by hand instead of pumping a real binding.
typedef ChatStreamingFrameScheduler = void Function(VoidCallback onFrame);

void _scheduleNextFrame(VoidCallback onFrame) => SchedulerBinding.instance.scheduleFrameCallback((_) => onFrame());

/// The text of one streaming chat row, as a [ValueListenable] of [Markdown].
///
/// Transport-agnostic: whatever delivers the deltas (SSE, a socket, a test)
/// calls [append]. The message object of the row stays fixed and its tile
/// renders this controller through [ChatStreamingBody]; the viewport never
/// sees a new message while the text grows, only a relayout of the row. When
/// the stream ends, [settle] hands over the final text and the host replaces
/// the row with one `updateMessage`.
///
/// Many [append]s inside a frame cost one parse and one notification: they are
/// buffered and fed to a `StreamingMarkdownParser` (which re-parses only the
/// still-growing tail) when the frame comes.
///
/// Lifecycle: live, then [settle]d or disposed. [append] after [settle] or
/// [dispose] is a silent no-op (a late delta of a cancelled stream is normal
/// and must not throw or revive the row). [settle] after [settle] is a no-op
/// too; after [dispose] it is also a no-op.
class ChatStreamingBodyController extends ChangeNotifier implements ValueListenable<Markdown> {
  /// Creates a live controller with no text.
  ///
  /// [decoder] configures the parser as for `Markdown.fromString`.
  /// [frameScheduler] defaults to the next engine frame.
  ChatStreamingBodyController({
    MarkdownDecoder decoder = const MarkdownDecoder(),
    ChatStreamingFrameScheduler frameScheduler = _scheduleNextFrame,
  }) : _parser = StreamingMarkdownParser(decoder: decoder),
       _schedule = frameScheduler;

  final StreamingMarkdownParser _parser;
  final ChatStreamingFrameScheduler _schedule;
  final StringBuffer _pending = StringBuffer();

  Markdown _value = const Markdown.empty();
  bool _frameRequested = false;
  bool _settled = false;
  bool _disposed = false;

  @override
  Markdown get value => _value;

  /// Whether [settle] has run: the text is final and [append] does nothing.
  bool get isSettled => _settled;

  /// Buffers [delta]; the text appears on the next frame, all deltas of that
  /// frame as one notification. Empty deltas are ignored.
  void append(String delta) {
    if (_settled || _disposed || delta.isEmpty) return;
    _pending.write(delta);
    if (_frameRequested) return;
    _frameRequested = true;
    _schedule(_flush);
  }

  /// Replaces everything accumulated (buffered deltas included) with
  /// [finalText] and notifies once, now: the last delta of a stream is often
  /// not the whole truth (the server's own final text wins).
  void settle(String finalText) {
    if (_settled || _disposed) return;
    _settled = true;
    _pending.clear();
    _parser
      ..reset()
      ..add(finalText);
    _value = _parser.current;
    notifyListeners();
  }

  void _flush() {
    _frameRequested = false;
    // A frame callback outlives a settle/dispose that came after the append.
    if (_settled || _disposed || _pending.isEmpty) return;
    final delta = _pending.toString();
    _pending.clear();
    _value = _parser.add(delta);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pending.clear();
    super.dispose();
  }
}

/// The body of a streaming row: renders a [ChatStreamingBodyController] and
/// registers each text it shows with the selection facade, so selection and
/// copy work while the row is live and after it settles.
///
/// Put it in the tile of a message that stays fixed while the text grows.
/// Everything around the text (bubble, ids, tiles) stays the host's. After the
/// swap to the final message the tile may keep showing this widget on a
/// settled controller, or switch to a plain `ChatMarkdownBody`; the
/// registration is the same, keyed by [messageId].
class ChatStreamingBody extends StatefulWidget {
  /// Creates the body of [messageId] fed by [body].
  const ChatStreamingBody({
    required this.controller,
    required this.messageId,
    required this.body,
    this.theme,
    this.autoscroll,
    this.embedResolver,
    super.key,
  });

  /// The engine selection controller.
  final ChatSelectionController controller;

  /// Id of the row; keys the selection registry.
  final int messageId;

  /// The text source.
  final ChatStreamingBodyController body;

  /// See [ChatMarkdownBody.theme].
  final MarkdownThemeData? theme;

  /// See [ChatMarkdownBody.autoscroll].
  final ChatMarkdownAutoscrollOptions? autoscroll;

  /// See [ChatMarkdownBody.embedResolver].
  final InlineEmbedResolver? embedResolver;

  @override
  State<ChatStreamingBody> createState() => _ChatStreamingBodyState();
}

class _ChatStreamingBodyState extends State<ChatStreamingBody> {
  Object? _token;
  bool _registers = true;

  @override
  void initState() {
    super.initState();
    widget.body.addListener(_put);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registers = ChatMarkdownBodyRegistration.allows(context);
    if (registers == _registers && _token != null) return;
    _registers = registers;
    _put();
  }

  @override
  void didUpdateWidget(ChatStreamingBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.body != widget.body) {
      oldWidget.body.removeListener(_put);
      widget.body.addListener(_put);
    }
    if (oldWidget.messageId != widget.messageId || oldWidget.controller != widget.controller) {
      _remove(oldWidget.controller, oldWidget.messageId);
    }
    _put();
  }

  @override
  void dispose() {
    widget.body.removeListener(_put);
    _remove(widget.controller, widget.messageId);
    super.dispose();
  }

  void _remove(ChatSelectionController controller, int messageId) {
    if (_token == null) return;
    controller.removeBody(messageId, token: _token);
    _token = null;
  }

  void _put() {
    if (!_registers) return;
    _token = widget.controller.putBody(widget.messageId, widget.body.value, order: widget.messageId, token: _token);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Markdown>(
    valueListenable: widget.body,
    builder: (context, markdown, _) => ChatMarkdownBody(
      controller: widget.controller,
      messageId: widget.messageId,
      markdown: markdown,
      theme: widget.theme,
      autoscroll: widget.autoscroll,
      embedResolver: widget.embedResolver,
    ),
  );
}
