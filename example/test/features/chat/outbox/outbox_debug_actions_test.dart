import 'package:chat_scroll_view_example/src/features/chat/outbox/outbox_debug_actions.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chat = 'c1';

  late RecordingDiagnostics diagnostics;
  late _RecordingHooks hooks;
  late int exits;
  late OutboxDebugActions actions;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    hooks = _RecordingHooks();
    exits = 0;
    actions = OutboxDebugActions(engine: hooks, exit: () => exits++);
  });

  tearDown(() => actions.dispose());

  List<Object?> actionsReported() => [
    for (final event in diagnostics.events)
      if (event.op == OutboxDebugOp.debugAction) event.fields['action'],
  ];

  test('kill in 3 s reports the action first, as a warning, then exits at '
      '3 s and not before', () {
    fakeAsync((async) {
      actions.killIn(chat);

      final event = diagnostics.events.single;
      expect(event.op, OutboxDebugOp.debugAction);
      expect(event.level, ChatEventLevel.warning);
      expect(event.category, ChatEventCategory.outbox);
      expect(event.fields['action'], 'killIn3s');
      expect(event.correlation.chatId, chat);
      expect(actions.killPending.value, isTrue);

      async.elapse(const Duration(milliseconds: 2900));
      expect(exits, 0);
      async.elapse(const Duration(milliseconds: 100));
      expect(exits, 1);
    });
  });

  test('a pending kill can be cancelled', () {
    fakeAsync((async) {
      actions.killIn(chat);
      async.elapse(OutboxDebugActions.guardWindow);
      actions.cancelKill();
      async.elapse(const Duration(seconds: 5));

      expect(exits, 0);
      expect(actions.killPending.value, isFalse);
    });
  });

  test('cut and restore the network report their actions and reach the '
      'engine hook', () {
    fakeAsync((async) {
      actions.cutNetwork(chat);
      expect(hooks.cuts, [true]);
      expect(actions.networkCut.value, isTrue);

      async.elapse(OutboxDebugActions.guardWindow);
      actions.restoreNetwork(chat);
      expect(hooks.cuts, [true, false]);
      expect(actions.networkCut.value, isFalse);

      expect(actionsReported(), ['cutNetwork', 'restoreNetwork']);
      expect(
        diagnostics.events.every((e) => e.level == ChatEventLevel.warning),
        isTrue,
      );
    });
  });

  test('a system interruption reports first and runs the engine hook', () {
    hooks.onInterrupt = () {
      expect(actionsReported(), ['systemInterruption']);
      return 2;
    };

    expect(actions.simulateSystemInterruption(chat), 2);
    expect(hooks.interruptions, 1);
  });

  test('a burst of taps on an action acts once', () {
    fakeAsync((async) {
      for (var i = 0; i < 5; i++) {
        actions
          ..killIn(chat)
          ..cutNetwork(chat)
          ..simulateSystemInterruption(chat);
      }
      async.elapse(const Duration(seconds: 3));

      expect(exits, 1);
      expect(hooks.cuts, [true]);
      expect(hooks.interruptions, 1);
      expect(actionsReported(), [
        'killIn3s',
        'cutNetwork',
        'systemInterruption',
      ]);
    });
  });

  test(
    'without an engine the engine actions do nothing and report nothing',
    () {
      final bare = OutboxDebugActions(engine: null, exit: () => exits++);
      addTearDown(bare.dispose);

      bare.cutNetwork(chat);
      expect(bare.simulateSystemInterruption(chat), 0);

      expect(actionsReported(), isEmpty);
      expect(bare.networkCut.value, isFalse);
    },
  );

  test('dispose cancels a pending kill', () {
    fakeAsync((async) {
      actions
        ..killIn(chat)
        ..dispose();
      async.elapse(const Duration(seconds: 5));
      expect(exits, 0);
    });
  });
}

final class _RecordingHooks implements TransferDebugHooks {
  final List<bool> cuts = [];
  int interruptions = 0;
  int Function() onInterrupt = () => 0;

  @override
  Null snapshot() => null;

  @override
  void cutNetwork({required bool cut}) => cuts.add(cut);

  @override
  int simulateSystemInterruption() {
    interruptions++;
    return onInterrupt();
  }
}
