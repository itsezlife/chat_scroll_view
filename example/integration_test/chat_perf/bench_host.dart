/// The bench host: a minimal host of the public `ChatScrollView` API with
/// fixed deterministic bubble builders, so a bubble or screen change cannot
/// move engine numbers.
///
/// Public API only: the `@internal` scroll mutators are never called; scenarios
/// drive the viewport by pointer gestures and the public controller.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus.dart';
import 'corpus_rich.dart';
import 'perf_host.dart';

/// Fixed bubble: one rounded rectangle and one paragraph, nothing else.
Widget benchBubble(
  BuildContext context,
  int id,
  IChatMessage? message,
  ChatMessageStatus status,
  MessageRunLayout runLayout,
) {
  if (message case BenchMessage(:final text)) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: id.isEven ? const Color(0xFFE3F2FD) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ),
      ),
    );
  }
  return const SizedBox(height: 60);
}

/// The inline separator and floating date pill of the bench host.
Widget _datePill(BuildContext context, Object bucket, DateTime date) => Center(
  child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF455A64),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          '${date.year}-${date.month}-${date.day}',
          style: const TextStyle(fontSize: 12, color: Color(0xFFFFFFFF)),
        ),
      ),
    ),
  ),
);

/// Registers [markdown] for [messageId] with [selection] while mounted and
/// draws it with the viewport's markdown body, so the per-body scope owns the
/// continuous press.
class _BenchMarkdownBody extends StatefulWidget {
  const _BenchMarkdownBody({
    required this.selection,
    required this.messageId,
    required this.markdown,
  });

  final ChatSelectionController selection;
  final int messageId;
  final Markdown markdown;

  @override
  State<_BenchMarkdownBody> createState() => _BenchMarkdownBodyState();
}

class _BenchMarkdownBodyState extends State<_BenchMarkdownBody> {
  Object? _token;

  @override
  void initState() {
    super.initState();
    if (ChatMarkdownBodyRegistration.allows(context)) {
      _token = widget.selection.putBody(
        widget.messageId,
        widget.markdown,
        order: widget.messageId,
      );
    }
  }

  @override
  void dispose() {
    if (_token != null) {
      widget.selection.removeBody(widget.messageId, token: _token);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: const TextStyle(fontSize: 15, height: 1.4, color: Color(0xFF1A1A1A)),
    child: ChatMarkdownBody(
      controller: widget.selection,
      messageId: widget.messageId,
      markdown: widget.markdown,
    ),
  );
}

/// A mounted viewport over a seeded corpus.
final class BenchHost implements PerfHost {
  BenchHost._(this.tester, this.source, this.controller, this.selection) {
    selection.addInteractionListener(interactions.add);
    SchedulerBinding.instance.addPersistentFrameCallback((_) => frameCount++);
  }

  /// Mounts a fresh host over [corpus], at the newest message.
  static Future<BenchHost> mount(
    WidgetTester tester,
    BenchCorpus corpus, {
    bool floatingDayHeader = false,
  }) async {
    final source = BenchDataSource(corpus);
    final controller = ChatScrollController();
    // The mobile policy is explicit: it is what the Android reference device
    // defaults to, and a desktop dev run measures the same path.
    final selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.mobile(),
      // The host owns the clipboard: a code tap reports `ChatCodeActivated`.
      copyCodeOnClick: false,
    );
    final host = BenchHost._(tester, source, controller, selection);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              host._menuContext = context;
              return ChatScrollView(
                reverse: true,
                dataSource: source,
                controller: controller,
                selectionController: selection,
                onIdleMessageTap: host._onIdleTap,
                isSelfMessage: (m) => m.sender == kBenchSelf,
                messageBuilder: host._buildMessage,
                scrollActivityTiming: floatingDayHeader
                    ? const ChatScrollActivityTiming()
                    : null,
                dayHeaderDelegate: floatingDayHeader
                    ? const ChatPushingDayHeader()
                    : const ChatFadingDayHeader(),
                dateSeparatorBuilder: floatingDayHeader ? _datePill : null,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return host;
  }

  @override
  final WidgetTester tester;
  final BenchDataSource source;
  @override
  final ChatScrollController controller;
  final ChatSelectionController selection;

  /// Interactions the selection facade reported, in order.
  final interactions = <ChatSelectionInteraction>[];

  /// Keys of the designated targets' bubbles and markdown bodies.
  final Map<BenchTarget, GlobalKey> rowKeys = {
    for (final t in BenchTarget.values) t: GlobalKey(debugLabel: 'row $t'),
  };
  final Map<BenchTarget, GlobalKey> bodyKeys = {
    for (final t in BenchTarget.values) t: GlobalKey(debugLabel: 'body $t'),
  };

  final _markdowns = <int, Markdown>{};
  final clock = Stopwatch()..start();
  late BuildContext _menuContext;

  /// When the last idle message tap request arrived, on [clock].
  Duration? lastMenuRequestAt;
  bool menuOpen = false;

  /// Pointer-up to the idle tap request of the last menu presented.
  Duration? menuRequestLatency;

  /// Frames drawn since the host mounted.
  int frameCount = 0;

  /// When the last pointer lifted, on [clock].
  Duration? lastPointerUpAt;

  void _onIdleTap(ChatMessageMenuRequest request) {
    lastMenuRequestAt = clock.elapsed;
    if (lastPointerUpAt case final up?) menuRequestLatency = clock.elapsed - up;
    menuOpen = true;
    ChatMessageMenu.show(
      context: _menuContext,
      messageRect: request.slotGlobal,
      tapGlobal: request.tapGlobal,
      surfaceRect: request.surfaceGlobal,
      surfaceShape: request.surfaceShape,
      visibleRect: request.bandGlobal,
      selectionPolicy: const ChatSelectionPolicy.mobile(),
      items: const [
        ChatMessageMenuItem(id: 'reply', label: 'Reply', icon: Icons.reply),
        ChatMessageMenuItem(id: 'copy', label: 'Copy', icon: Icons.copy),
        ChatMessageMenuItem(
          id: 'forward',
          label: 'Forward',
          icon: Icons.forward,
        ),
      ],
    ).whenComplete(() => menuOpen = false);
  }

  Widget _buildMessage(
    BuildContext context,
    int id,
    IChatMessage? message,
    ChatMessageStatus status,
    MessageRunLayout runLayout,
  ) {
    if (message case BenchMessage(:final text, markdown: true)) {
      final target = BenchTarget.values.where((t) => t.id == id).firstOrNull;
      final markdown = _markdowns.putIfAbsent(
        id,
        () => Markdown.fromString(text),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: DecoratedBox(
          key: target == null ? null : rowKeys[target],
          decoration: BoxDecoration(
            color: id.isEven
                ? const Color(0xFFE3F2FD)
                : const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: KeyedSubtree(
              key: target == null ? null : bodyKeys[target],
              child: _BenchMarkdownBody(
                selection: selection,
                messageId: id,
                markdown: markdown,
              ),
            ),
          ),
        ),
      );
    }
    return benchBubble(context, id, message, status, runLayout);
  }

  /// The global rect of the render box under [key].
  Rect rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      throw StateError('target is not mounted: $key');
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  int get history => source.corpus.count;

  @override
  Finder get viewport => find.byType(ChatScrollView);

  /// Removes the viewport, releases its controller and returns the process to
  /// a comparable state, between scenarios: image caches cleared, memory
  /// pressure signalled (the engine drops its caches) and a GC settle awaited.
  @override
  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    selection.dispose();
    controller.dispose();
    source.dispose();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    PaintingBinding.instance.handleMemoryPressure();
    await _gcSettle(tester);
  }

  /// Dart offers no forced collection: idle in real time with frames running
  /// so the collector finishes before the next scenario's window.
  static Future<void> _gcSettle(WidgetTester tester) async {
    final end = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
