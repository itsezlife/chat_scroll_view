import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/ime_comparability.dart';
import '../../integration_test/chat_perf/registry.dart';
import '../../integration_test/chat_perf/scenarios/ime_scenarios.dart';
import '../../integration_test/chat_perf/scenarios/keyboard_scenarios.dart';

final class _RecordingContext implements ImeContext {
  final calls = <String>[];
  String? open;
  bool primed = false;

  void _log(String call) => calls.add(open == null ? '$call outside' : call);

  @override
  int get history => 20000;

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
  Future<void> openKeyboard() async => _log('open keyboard');

  @override
  Future<void> closeKeyboard() async => _log('close keyboard');

  @override
  Future<void> openPanel() async => _log('open panel');

  @override
  Future<void> closePanel() async => _log('close panel');

  @override
  Future<void> switchToPanel() async => _log('switch to panel');

  @override
  Future<void> growComposer({
    required int lines,
    required Duration after,
  }) async => _log('grow $lines');

  @override
  Future<void> fling(double dy, Duration duration) async => _log('fling');

  @override
  Future<void> idle(Duration duration) async => _log('hold');

  @override
  Future<({int frames, int anchorId, double anchorOffset})> animateTo(
    int id,
    Duration duration,
  ) async {
    _log('animate');
    return (frames: 0, anchorId: id, anchorOffset: 0.0);
  }

  @override
  Future<void> settle() async => _log('settle');

  @override
  Future<void> control(Future<void> Function() body) async {
    calls.add('control');
    await body();
  }

  // Only the calls an IME scenario makes are implemented.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Scenario byId(String id) => imeScenarios.all.singleWhere((s) => s.id == id);

  List<String> windowOf(_RecordingContext ctx, String name) => ctx.calls
      .skipWhile((c) => c != 'begin $name')
      .takeWhile((c) => c != 'end $name')
      .toList();

  test('the real-IME family is registered next to the synthetic one', () {
    expect(imeScenarios.keys, [
      'kbd.open_tail@1',
      'kbd.close_tail@1',
      'kbd.open_mid_history@1',
      'kbd.open_mid_fling@1',
      'kbd.open_during_animate@1',
      'kbd.composer_growth@1',
      'panel.open_over_chat@1',
      'panel.keyboard_handoff@1',
      'kbd.interactive_dismiss@1',
    ]);
    final synthetic = keyboardScenarios.all.map((s) => s.id).toSet();
    final real = imeScenarios.all.map((s) => s.id).toSet();
    expect(real.intersection(synthetic), isEmpty);
    expect(
      imeScenarios.all.every((s) => s.subject == ScenarioSubject.realChat),
      isTrue,
    );
  });

  test('interactive dismiss is iOS only and says why it is skipped', () {
    final dismiss = byId('kbd.interactive_dismiss');
    expect(dismiss.onlyOn, 'ios');
    expect(dismiss.skipReasonOn('android'), contains('iOS'));
    expect(dismiss.skipReasonOn('ios'), isNull);
    for (final s in imeScenarios.all.where((s) => s != dismiss)) {
      expect(s.skipReasonOn('android'), isNull, reason: s.id);
    }
  });

  test('open_tail primes with one real open and close, then opens', () async {
    final ctx = _RecordingContext();
    await byId('kbd.open_tail').run(ctx);
    expect(ctx.primed, isTrue);
    expect(ctx.calls, [
      'seat tail outside',
      'open keyboard outside',
      'close keyboard outside',
      'begin open',
      'open keyboard',
      'end open',
    ]);
  });

  test('close_tail has the keyboard up before its window', () async {
    final ctx = _RecordingContext();
    await byId('kbd.close_tail').run(ctx);
    expect(
      ctx.calls.takeWhile((c) => c != 'begin close').last,
      'open keyboard outside',
    );
    expect(windowOf(ctx, 'close'), ['begin close', 'close keyboard']);
  });

  test('open_mid_history seats mid-history', () async {
    final ctx = _RecordingContext();
    await byId('kbd.open_mid_history').run(ctx);
    expect(ctx.calls.first, 'seat midHistory outside');
  });

  test('open_mid_fling flings in the window and pairs a control', () async {
    final ctx = _RecordingContext();
    await byId('kbd.open_mid_fling').run(ctx);
    expect(windowOf(ctx, 'open'), ['begin open', 'fling', 'open keyboard']);
    expect(ctx.calls.skipWhile((c) => c != 'control').toList(), [
      'control',
      'seat midHistory outside',
      'fling outside',
      'hold outside',
    ]);
  });

  test('open_during_animate animates while opening, with a control', () async {
    final ctx = _RecordingContext();
    await byId('kbd.open_during_animate').run(ctx);
    expect(windowOf(ctx, 'open'), containsAll(['animate', 'open keyboard']));
    final control = ctx.calls.skipWhile((c) => c != 'control').toList();
    expect(control, contains('animate outside'));
    expect(control, isNot(contains('open keyboard outside')));
  });

  test('composer_growth grows the composer while the keyboard opens', () async {
    final ctx = _RecordingContext();
    await byId('kbd.composer_growth').run(ctx);
    expect(windowOf(ctx, 'open'), containsAll(['open keyboard', 'grow 6']));
  });

  test('panel.open_over_chat opens a panel with no keyboard', () async {
    final ctx = _RecordingContext();
    await byId('panel.open_over_chat').run(ctx);
    expect(windowOf(ctx, 'open'), ['begin open', 'open panel']);
    expect(ctx.primed, isTrue);
    expect(ctx.calls, isNot(contains('open keyboard')));
  });

  test('panel.keyboard_handoff starts with the keyboard up', () async {
    final ctx = _RecordingContext();
    await byId('panel.keyboard_handoff').run(ctx);
    expect(
      ctx.calls.takeWhile((c) => c != 'begin handoff').last,
      'open keyboard outside',
    );
    expect(windowOf(ctx, 'handoff'), ['begin handoff', 'switch to panel']);
  });

  test('interactive dismiss refuses to run where there is no such gesture', () {
    expect(
      () => byId('kbd.interactive_dismiss').run(_RecordingContext()),
      throwsStateError,
    );
  });

  group('imeComparable', () {
    test('within 2 percent of the baseline is comparable', () {
      expect(imeComparable(settledPx: 1008, baselinePx: 1008), isTrue);
      expect(imeComparable(settledPx: 1028, baselinePx: 1008), isTrue);
      expect(imeComparable(settledPx: 988, baselinePx: 1008), isTrue);
    });

    test('more than 2 percent off is not comparable', () {
      expect(imeComparable(settledPx: 1029, baselinePx: 1008), isFalse);
      expect(imeComparable(settledPx: 900, baselinePx: 1008), isFalse);
    });

    test('a zero baseline is comparable only to zero', () {
      expect(imeComparable(settledPx: 0, baselinePx: 0), isTrue);
      expect(imeComparable(settledPx: 1, baselinePx: 0), isFalse);
    });
  });
}
