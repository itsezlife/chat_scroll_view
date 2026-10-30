import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/keyboard_ramp.dart';
import '../../integration_test/chat_perf/registry.dart';
import '../../integration_test/chat_perf/scenarios/keyboard_scenarios.dart';

final class _RecordingContext implements KeyboardContext {
  final calls = <String>[];
  String? open;
  bool primed = false;

  void _log(String call) => calls.add(open == null ? '$call outside' : call);

  @override
  Future<void> measure(
    String name,
    Future<void> Function() body, {
    Future<void> Function()? primer,
  }) async {
    primed = primer != null;
    if (primer != null) await primer();
    calls.add('begin $name');
    open = name;
    await body();
    open = null;
    calls.add('end $name');
  }

  @override
  Future<void> seat(KeyboardSeat seat) async => _log('seat ${seat.name}');

  @override
  Future<void> ramp(InsetCurve curve) async {
    final end = curve.at(curve.durationMs);
    _log(
      'ramp ${curve.at(0) < end ? 'open' : 'close'} '
      '${end == 1 || curve.at(0) == 1 ? 'full' : 'low'}',
    );
  }

  @override
  Future<void> fling(double dy, Duration duration) async => _log('fling');

  @override
  Future<void> idle(Duration duration) async => _log('hold');

  // Only the calls a keyboard scenario makes are implemented.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> handOffToPanel(InsetCurve curve) async => _log('handoff');

  @override
  Future<void> control(Future<void> Function() body) async {
    calls.add('control');
    await body();
  }

  @override
  Future<void> drag(double dy, Duration duration) async => _log('drag');

  @override
  Future<void> settle() async => _log('settle');
}

void main() {
  Scenario byId(String id) =>
      keyboardScenarios.all.singleWhere((s) => s.id == id);

  test('the five synthetic scenarios are registered, shared-process', () {
    expect(keyboardScenarios.keys, [
      'kbd.synthetic_open_tail@1',
      'kbd.synthetic_close_tail@1',
      'kbd.synthetic_open_mid_history@1',
      'kbd.synthetic_open_mid_fling@1',
      'kbd.synthetic_handoff@1',
    ]);
    expect(keyboardScenarios.all.where((s) => s.cold), isEmpty);
  });

  test('open_tail measures one open ramp, primed outside the window', () async {
    final ctx = _RecordingContext();
    await byId('kbd.synthetic_open_tail').run(ctx);
    expect(ctx.primed, isTrue);
    expect(ctx.calls, [
      'seat tail outside',
      'ramp open low outside',
      'ramp close low outside',
      'begin open',
      'ramp open full',
      'end open',
    ]);
  });

  test('close_tail opens fully before its window and closes inside', () async {
    final ctx = _RecordingContext();
    await byId('kbd.synthetic_close_tail').run(ctx);
    expect(ctx.calls.takeWhile((c) => c != 'begin close'), [
      'seat tail outside',
      'ramp open low outside',
      'ramp close low outside',
      'ramp open full outside',
    ]);
    expect(ctx.calls.skipWhile((c) => c != 'begin close'), [
      'begin close',
      'ramp close full',
      'end close',
    ]);
  });

  test('open_mid_history seats in the middle of the history', () async {
    final ctx = _RecordingContext();
    await byId('kbd.synthetic_open_mid_history').run(ctx);
    expect(ctx.calls.first, 'seat midHistory outside');
  });

  test('open_mid_fling flings inside the window and pairs a control', () async {
    final ctx = _RecordingContext();
    await byId('kbd.synthetic_open_mid_fling').run(ctx);
    final window = ctx.calls.skipWhile((c) => c != 'begin open').toList();
    expect(window.take(4), [
      'begin open',
      'fling',
      'ramp open full',
      'end open',
    ]);
    // The control repeats the seat and fling and applies no inset change.
    final control = window.skipWhile((c) => c != 'control').toList();
    expect(control, [
      'control',
      'seat midHistory outside',
      'fling outside',
      'hold outside',
    ]);
  });

  test(
    'handoff opens the panel as the keyboard closes, in the window',
    () async {
      final ctx = _RecordingContext();
      await byId('kbd.synthetic_handoff').run(ctx);
      expect(
        ctx.calls.takeWhile((c) => c != 'begin handoff').last,
        'ramp open full outside',
      );
      expect(ctx.calls.skipWhile((c) => c != 'begin handoff'), [
        'begin handoff',
        'handoff',
        'end handoff',
      ]);
    },
  );

  test('a scenario refuses a context that cannot drive the keyboard', () {
    final plain = _PlainContext();
    expect(() => byId('kbd.synthetic_open_tail').run(plain), throwsStateError);
  });

  test('the curve profile is a parameter', () {
    final stepped = buildKeyboardScenarios(
      const InsetCurveProfile(
        name: 'step',
        heightDp: 300,
        open: InsetCurve([(0, 0), (1, 1)]),
        close: InsetCurve([(0, 1), (1, 0)]),
      ),
    );
    expect(stepped.keys, keyboardScenarios.keys);
  });
}

final class _PlainContext implements ScenarioContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> drag(double dy, Duration duration) async {}

  @override
  Future<void> measure(
    String name,
    Future<void> Function() body, {
    Future<void> Function()? primer,
  }) async {}

  @override
  Future<void> settle() async {}
}
