/// The bench host: a minimal host of the public `ChatScrollView` API with
/// fixed deterministic bubble builders, so a bubble or screen change cannot
/// move engine numbers.
///
/// Public API only: the `@internal` scroll mutators are never called; scenarios
/// drive the viewport by pointer gestures and the public controller.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bench_setup.dart';
import 'churn.dart';
import 'corpus.dart';
import 'perf_host.dart';

/// Fixed bubble: one rounded rectangle and one paragraph, nothing else, in a
/// probe wrapper that lets the host read its geometry and count placeholders.
Widget benchBubble(
  BuildContext context,
  int id,
  IChatMessage? message,
  ChatMessageStatus status,
  MessageRunLayout runLayout,
) => _ProbedRow(
  id: id,
  placeholder: message == null,
  child: _bubbleBody(context, id, message, status, runLayout),
);

Widget _bubbleBody(
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

/// Live rows, read by the host after each frame.
final class BenchProbe {
  final _rows = <int, BuildContext>{};
  int placeholders = 0;
  final Stopwatch sinceMount = Stopwatch();
  double? firstBuildMs;

  /// Ids of loaded rows intersecting [viewport], ascending, with their bottom
  /// edges.
  Map<int, double> visibleBottoms(Rect viewport) {
    final out = <int, double>{};
    for (final e in _rows.entries) {
      final box = e.value.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom > viewport.top && top < viewport.bottom) {
        // The band's bottom edge, clipped to the viewport: a row taller than
        // the viewport has its bottom off screen.
        out[e.key] = bottom < viewport.bottom ? bottom : viewport.bottom;
      }
    }
    return Map.fromEntries(out.entries.toList()..sort((a, b) => a.key - b.key));
  }
}

BenchProbe _probe = BenchProbe();

class _ProbedRow extends StatefulWidget {
  const _ProbedRow({
    required this.id,
    required this.placeholder,
    required this.child,
  });

  final int id;
  final bool placeholder;
  final Widget child;

  @override
  State<_ProbedRow> createState() => _ProbedRowState();
}

class _ProbedRowState extends State<_ProbedRow> {
  late final BenchProbe _p = _probe;

  @override
  void initState() {
    super.initState();
    if (widget.placeholder) {
      _p.placeholders++;
    } else {
      _p._rows[widget.id] = context;
      _p.firstBuildMs ??= _p.sinceMount.elapsedMicroseconds / 1000;
    }
  }

  @override
  void didUpdateWidget(_ProbedRow old) {
    super.didUpdateWidget(old);
    if (old.placeholder != widget.placeholder) {
      if (widget.placeholder) {
        _p.placeholders++;
        _p._rows.remove(widget.id);
      } else {
        _p.placeholders--;
        _p._rows[widget.id] = context;
        _p.firstBuildMs ??= _p.sinceMount.elapsedMicroseconds / 1000;
      }
    }
  }

  @override
  void dispose() {
    if (widget.placeholder) {
      _p.placeholders--;
    } else if (_p._rows[widget.id] == context) {
      _p._rows.remove(widget.id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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

/// A mounted viewport over a seeded corpus.
final class BenchHost implements PerfHost, ChurnHost {
  BenchHost._(
    this.tester,
    this.source,
    this.controller,
    this.probe,
    this.unread,
    this.viewportKey,
  );

  /// Mounts a fresh host over [corpus], at the newest message.
  static Future<BenchHost> mount(
    WidgetTester tester,
    BenchCorpus corpus, {
    BenchSetup setup = const BenchSetup(),
    bool floatingDayHeader = false,
  }) async {
    final source = BenchDataSource(corpus, setup: setup);
    final controller = ChatScrollController();
    final unread = ValueNotifier<int?>(null);
    final viewportKey = GlobalKey();
    final probe = _probe = BenchProbe();
    probe.sinceMount.start();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: ChatScrollView(
            key: viewportKey,
            reverse: true,
            dataSource: source,
            controller: controller,
            isSelfMessage: (m) => m.sender == kBenchSelf,
            messageBuilder: benchBubble,
            unreadBoundary: unread,
            unreadSeparatorBuilder: (_) => const SizedBox(
              height: 28,
              child: Center(child: Text('Unread messages')),
            ),
            scrollActivityTiming: floatingDayHeader
                ? const ChatScrollActivityTiming()
                : null,
            dayHeaderDelegate: floatingDayHeader
                ? const ChatPushingDayHeader()
                : const ChatFadingDayHeader(),
            dateSeparatorBuilder: floatingDayHeader ? _datePill : null,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return BenchHost._(tester, source, controller, probe, unread, viewportKey);
  }

  @override
  final WidgetTester tester;
  final BenchDataSource source;
  @override
  final ChatScrollController controller;
  final BenchProbe probe;
  final ValueNotifier<int?> unread;
  final GlobalKey viewportKey;

  @override
  double? get firstBuildMs => probe.firstBuildMs;

  @override
  int get newestId => source.newestKnownId ?? 0;

  @override
  void insert({required bool self}) {
    final id = source.nextInsertId;
    source.insertMessage(
      BenchMessage(
        id: id,
        sender: self ? kBenchSelf : 'user0',
        text: self ? 'Sent message.' : 'Incoming message.',
        createdAt: DateTime.utc(2026).add(Duration(minutes: id * 20)),
      ),
      reason: 'bench.insert',
    );
  }

  @override
  void edit(int id, {required bool taller}) {
    final current = source.getMessage(id);
    if (current is! BenchMessage) return;
    final original = source.corpus.messageAt(id).text;
    source.updateMessage(
      current.edited(taller ? List.filled(5, original).join('\n') : original),
      reason: 'bench.edit',
    );
  }

  @override
  void remove(int id) => source.removeMessages([id], reason: 'bench.remove');

  @override
  void setUnreadBoundary(int? id) => unread.value = id;

  /// The viewport's rectangle in global coordinates.
  Rect get viewportRect {
    // Not through the tester: its guarded APIs reject a read during a gesture.
    final box = viewportKey.currentContext!.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  int? get visibleNonAnchorId {
    final anchor = controller.anchorMessageId;
    for (final id in probe.visibleBottoms(viewportRect).keys) {
      if (id != anchor) return id;
    }
    return null;
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
    controller.dispose();
    unread.dispose();
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
