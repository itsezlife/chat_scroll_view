import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/registry.dart';
import '../../integration_test/chat_perf/scenarios/scroll_scenarios.dart';

final class _RecordingContext implements ScenarioContext {
  final calls = <String>[];
  double totalDragDp = 0;
  Duration totalDrag = Duration.zero;
  String? open;

  @override
  Future<void> measure(String name, Future<void> Function() body) async {
    calls.add('begin $name');
    open = name;
    await body();
    open = null;
    calls.add('end $name');
  }

  @override
  Future<void> drag(double dy, Duration duration) async {
    calls.add(open == null ? 'drag outside' : 'drag inside');
    if (open != null) {
      totalDragDp += dy.abs();
      totalDrag += duration;
    }
  }

  @override
  Future<void> settle() async => calls.add('settle');
}

void main() {
  Scenario slow() =>
      scrollScenarios.all.singleWhere((s) => s.id == 'scroll.drag_slow');

  test('scroll.drag_slow is registered with its declared window', () {
    expect(slow().key, 'scroll.drag_slow@1');
    expect(slow().windows, ['drag']);
  });

  test(
    'only declared windows are measured; slow drags last about 8 s',
    () async {
      final ctx = _RecordingContext();
      await slow().run(ctx);
      final windows = [
        for (final c in ctx.calls)
          if (c.startsWith('begin ')) c.substring(6),
      ];
      expect(windows, slow().windows);
      // The warm-up drag stays outside the window.
      expect(ctx.calls.first, 'drag outside');
      expect(ctx.totalDrag.inMilliseconds, inInclusiveRange(7500, 8500));
      // About 400 dp per 1.5 s.
      expect(
        ctx.totalDragDp / (ctx.totalDrag.inMilliseconds / 1000),
        closeTo(400 / 1.5, 1),
      );
    },
  );
}
