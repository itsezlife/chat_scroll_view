/// Selection, menu and rich-text scenarios on the bench host (spec 7.4).
///
/// They run on the mobile selection policy with held-pointer gestures, aim at
/// the designated targets of the `rich` profile and assert the exact outcomes
/// a window needs to be valid from the public selection facade.
library;

import 'dart:ui';

import 'package:chat_scroll_view/chat_scroll_view.dart';

import '../corpus.dart';
import '../corpus_rich.dart';
import '../gesture_driver.dart';
import '../metrics.dart';
import '../registry.dart';

/// Long enough for the long-press recognizer, in live wall time.
const _hold = Duration(milliseconds: 600);

/// Two lines of the bench paragraph (15 sp at a 1.4 line height).
const _lineHeight = 21.0;

void _require(bool ok, String what) {
  if (!ok) throw StateError('scenario outcome invalid: $what');
}

/// Where the first line of [target]'s body starts, a few glyphs in.
Offset _firstLine(GestureDriver g, BenchTarget target) =>
    g.bodyRect(target).topLeft + const Offset(24, _lineHeight / 2);

Metric _exact(num v) =>
    Metric(v.toDouble(), kind: MetricKind.exact, role: MetricRole.headline);

Metric _ms(num v) =>
    Metric(v.toDouble(), kind: MetricKind.ms, role: MetricRole.diagnostic);

Metric _count(num v) =>
    Metric(v.toDouble(), kind: MetricKind.count, role: MetricRole.diagnostic);

/// Message-selects the paragraph with one long-press, outside any window.
Future<void> _messageSelectParagraph(GestureDriver g) async {
  await g.seatTarget(BenchTarget.plainParagraph);
  final p = await g.down(_firstLine(g, BenchTarget.plainParagraph));
  await p.hold(_hold);
  await p.up();
  await g.frames(30);
  _require(
    g.state.selectedIds.length == 1 &&
        g.state.selectedIds.single == BenchTarget.plainParagraph.id,
    'the paragraph is not message-selected',
  );
}

/// `sel.message_enter_exit`: long-press row A, tap row B, clear.
final _messageEnterExit = Scenario(
  id: 'sel.message_enter_exit',
  version: 1,
  windows: const ['select'],
  profile: BenchProfile.rich,
  run: (ctx) async {
    final g = ctx.gestures;
    await g.seatTarget(BenchTarget.plainParagraph);
    final a = BenchTarget.plainParagraph.id;
    final b = BenchTarget.linkLine.id;
    Duration? enter;
    final ids = <Set<int>>[];
    await ctx.measure('select', () async {
      await g.frames(10);
      final p = await g.down(_firstLine(g, BenchTarget.plainParagraph));
      enter = await p.hold(_hold, watch: () => g.state.selectedIds.isNotEmpty);
      await p.up();
      ids.add(g.state.selectedIds);
      await g.frames(30);
      await g.tap(g.rowRect(BenchTarget.linkLine).topLeft + const Offset(6, 6));
      ids.add(g.state.selectedIds);
      await g.frames(30);
      g.clearSelection();
      ids.add(g.state.selectedIds);
      await g.frames(60);
    });
    _require(ids[0].length == 1 && ids[0].contains(a), 'long-press selects A');
    _require(ids[1].length == 2 && ids[1].containsAll([a, b]), 'a tap adds B');
    _require(ids[2].isEmpty, 'clear empties the selection');
    g.report('select', {
      'selected.after_enter': _exact(ids[0].length),
      'selected.after_add': _exact(ids[1].length),
      'selected.after_clear': _exact(ids[2].length),
      'enter_ms': _ms((enter ?? Duration.zero).inMicroseconds / 1000),
    });
  },
);

/// Second long-press on the selected paragraph, then the drag on the same
/// pointer. [toEdge] drags into the viewport's bottom edge zone instead.
Future<(Duration?, double)> _textDrag(
  GestureDriver g, {
  required bool toEdge,
}) async {
  var dpPerS = 0.0;
  final start = _firstLine(g, BenchTarget.plainParagraph);
  final p = await g.down(start);
  final entered = await p.hold(
    _hold,
    watch: () => g.state.isTextSelectionActive,
  );
  if (toEdge) {
    await p.moveBy(Offset(0, g.viewportRect.bottom - 4 - start.dy), frames: 60);
    const id = BenchTarget.plainParagraph;
    final clock = Stopwatch()..start();
    var travelled = 0.0;
    var last = g.bodyRect(id).top;
    var sampledMs = 0;
    for (var i = 0; i < 120; i++) {
      await g.frames(1);
      final rect = g.bodyRectIfMounted(id);
      if (rect == null) break;
      travelled += (rect.top - last).abs();
      last = rect.top;
      sampledMs = clock.elapsedMilliseconds;
    }
    dpPerS = sampledMs == 0 ? 0 : travelled * 1000 / sampledMs;
  } else {
    await p.moveBy(const Offset(160, 2 * _lineHeight), frames: 60);
  }
  await p.up();
  await g.frames(60);
  return (entered, dpPerS);
}

void _requireTextSelection(GestureDriver g) {
  final s = g.state;
  _require(s.isTextSelectionActive, 'text selection is active');
  _require(
    s.textSelectionSubject == BenchTarget.plainParagraph.id,
    'the subject is the paragraph',
  );
  _require(
    s.selectedIds.length == 1 &&
        s.selectedIds.single == BenchTarget.plainParagraph.id,
    'message selection is preserved',
  );
}

/// `sel.text_drag_extend`: enter text selection and drag 160 dp right, two
/// lines down.
final _textDragExtend = Scenario(
  id: 'sel.text_drag_extend',
  version: 1,
  windows: const ['drag'],
  profile: BenchProfile.rich,
  run: (ctx) async {
    final g = ctx.gestures;
    await _messageSelectParagraph(g);
    Duration? entered;
    await ctx.measure('drag', () async {
      await g.frames(10);
      entered = (await _textDrag(g, toEdge: false)).$1;
    });
    _requireTextSelection(g);
    _require(g.state.extentChars > 0, 'the drag extends the selection');
    g.report('drag', {
      'selection.extent_chars': _exact(g.state.extentChars),
      'text.enter_ms': _ms((entered ?? Duration.zero).inMicroseconds / 1000),
    });
  },
);

/// `sel.text_drag_autoscroll`: the same entry, dragged into the bottom edge
/// zone and held.
final _textDragAutoscroll = Scenario(
  id: 'sel.text_drag_autoscroll',
  version: 1,
  windows: const ['autoscroll'],
  profile: BenchProfile.rich,
  run: (ctx) async {
    final g = ctx.gestures;
    await _messageSelectParagraph(g);
    var dpPerS = 0.0;
    await ctx.measure('autoscroll', () async {
      await g.frames(10);
      dpPerS = (await _textDrag(g, toEdge: true)).$2;
    });
    _requireTextSelection(g);
    g.report('autoscroll', {
      'autoscroll.dp_per_s': Metric(
        dpPerS,
        kind: MetricKind.dp,
        role: MetricRole.diagnostic,
      ),
    });
  },
);

/// `sel.menu_open`: an idle tap presents the default mobile menu.
final _menuOpen = Scenario(
  id: 'sel.menu_open',
  version: 1,
  windows: const ['menu'],
  profile: BenchProfile.rich,
  run: (ctx) async {
    final g = ctx.gestures;
    await g.seatTarget(BenchTarget.plainParagraph);
    var openFrames = 0;
    var closeFrames = 0;
    await ctx.measure('menu', () async {
      await g.frames(10);
      await g.tap(
        g.rowRect(BenchTarget.plainParagraph).topLeft + const Offset(6, 6),
      );
      openFrames = await g.framesUntilIdle();
      _require(g.menuOpen, 'the menu is presented');
      await g.tap(const Offset(4, 4));
      closeFrames = await g.framesUntilIdle();
      await g.frames(60);
    });
    _require(!g.menuOpen, 'the menu is dismissed');
    final latency = g.menuRequestLatency;
    _require(latency != null, 'the idle tap reached the host');
    g.report('menu', {
      'menu.request_ms': _ms((latency ?? Duration.zero).inMicroseconds / 1000),
      'menu.open_frames': _count(openFrames),
      'menu.close_frames': _count(closeFrames),
    });
  },
);

/// `sel.code_block_highlight`: the mobile policy's tap target on a fenced
/// block is its bottom copy bar (ADR 014); the body is selectable text.
final _codeBlockHighlight = Scenario(
  id: 'sel.code_block_highlight',
  version: 1,
  windows: const ['tap'],
  profile: BenchProfile.rich,
  run: (ctx) async {
    final g = ctx.gestures;
    await g.seatTarget(BenchTarget.fencedCode);
    final body = g.bodyRect(BenchTarget.fencedCode);
    // The bar is 36 dp high inside a 4 dp outer padding.
    final bar = Offset(body.center.dx, body.bottom - 4 - 18);
    var frames = 0;
    await ctx.measure('tap', () async {
      await g.frames(10);
      await g.tap(bar);
      frames = await g.framesUntilIdle();
      await g.frames(60);
    });
    final hits = [
      for (final i in g.interactions)
        if (i case ChatCodeActivated(:final messageId)) messageId,
    ];
    _require(
      hits.length == 1 && hits.single == BenchTarget.fencedCode.id,
      'one code activation, got $hits',
    );
    g.report('tap', {
      'code.activations': _exact(hits.length),
      'highlight.frames': _count(frames),
    });
  },
);

/// `sel.link_tap_highlight`: a tap on the link line.
final _linkTapHighlight = Scenario(
  id: 'sel.link_tap_highlight',
  version: 1,
  windows: const ['tap'],
  profile: BenchProfile.rich,
  run: (ctx) async {
    final g = ctx.gestures;
    await g.seatTarget(BenchTarget.linkLine);
    var frames = 0;
    await ctx.measure('tap', () async {
      await g.frames(10);
      await g.tap(_firstLine(g, BenchTarget.linkLine));
      frames = await g.framesUntilIdle();
      await g.frames(60);
    });
    final hits = [
      for (final i in g.interactions)
        if (i case ChatLinkActivated(:final messageId, :final url))
          (messageId, url),
    ];
    _require(
      hits.length == 1 &&
          hits.single == (BenchTarget.linkLine.id, 'https://docs.flutter.dev'),
      'one link activation, got $hits',
    );
    g.report('tap', {
      'link.activations': _exact(hits.length),
      'highlight.frames': _count(frames),
    });
  },
);

/// Six flings of about 6.7k px/s toward older messages, each left to coast.
Future<void> _flings(ScenarioContext ctx) async {
  for (var i = 0; i < 6; i++) {
    await ctx.gestures.fling(400, const Duration(milliseconds: 60));
    await ctx.settle();
  }
}

double _ratio(double rich, double plain) => plain <= 0 ? 0 : rich / plain;

/// A fling scenario: the same fling over the plain region, then over [region]
/// seated mid-way, with the rich-over-plain ratios on the second window.
Scenario _richFling(String id, (int, int) region) => Scenario(
  id: id,
  version: 1,
  windows: const ['plain_fling', 'fling'],
  profile: BenchProfile.rich,
  run: (ctx) async {
    final g = ctx.gestures;
    Future<void> prime() => g.fling(60, const Duration(milliseconds: 60));
    await g.seat((kPlainRegion.$1 + kPlainRegion.$2) ~/ 2);
    await ctx.measure('plain_fling', () => _flings(ctx), primer: prime);
    await g.seat((region.$1 + region.$2) ~/ 2);
    await ctx.measure('fling', () => _flings(ctx), primer: prime);
    final plain = g.metricsOf('plain_fling');
    final rich = g.metricsOf('fling');
    Metric ratio(String key) => Metric(
      _ratio(rich[key]!.value, plain[key]!.value),
      kind: MetricKind.ratio,
      role: MetricRole.headline,
    );
    g.report('fling', {
      'rich_over_plain.build_p99': ratio('build_p99_share'),
      'rich_over_plain.raster_p99': ratio('raster_p99_share'),
    });
  },
);

/// The selection, menu and rich family.
final selectionScenarios = ScenarioRegistry([
  _messageEnterExit,
  _textDragExtend,
  _textDragAutoscroll,
  _menuOpen,
  _codeBlockHighlight,
  _linkTapHighlight,
  _richFling('rich.markdown_fling', kMarkdownRegion),
  _richFling('rich.code_fling', kCodeRegion),
]);
