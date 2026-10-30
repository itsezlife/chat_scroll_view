/// Real-keyboard and panel scenarios on the real chat screen (spec 7.3).
///
/// The twins of the synthetic family: the same transitions with the system
/// keyboard in place of a driven curve, so a transition can be compared with
/// and without the IME. Pure Dart: they speak only to an [ImeContext].
library;

import '../registry.dart';
import 'keyboard_scenarios.dart';

/// The probe's 6.7k px/s fling: 600 dp of finger travel in 90 ms, downward.
const _flingDy = 600.0;
const _flingTime = Duration(milliseconds: 90);

/// How long a control holds still where the keyboard would open.
const _controlHold = Duration(milliseconds: 600);

/// The animated scroll a keyboard opens during, and its length.
const _animateMessages = 400;
const _animateTime = Duration(milliseconds: 600);

/// The composer's growth: lines, and how long into the open it starts.
const _growLines = 6;
const _growAfter = Duration(milliseconds: 100);

/// What an IME scenario sees, on top of the generic [ScenarioContext].
abstract interface class ImeContext implements ScenarioContext {
  /// Moves the viewport to [seat] and settles, outside any window.
  Future<void> seat(KeyboardSeat seat);

  /// Taps the composer field and returns once the keyboard has settled.
  Future<void> openKeyboard();

  /// Unfocuses the field, asks the keyboard to hide and returns once it has
  /// settled.
  Future<void> closeKeyboard();

  /// Taps the composer's panel toggle with no keyboard up and returns once the
  /// panel has settled.
  Future<void> openPanel();

  /// Closes the open panel and returns once it has settled.
  Future<void> closePanel();

  /// Taps the panel toggle with the keyboard up, so the panel takes its slot,
  /// and returns once both have settled.
  Future<void> switchToPanel();

  /// Fills the composer's field with [lines] lines, [after] a delay.
  Future<void> growComposer({required int lines, required Duration after});

  /// Runs [body] as the control of the last measured window: the same script
  /// without the keyboard, not measured. Its end is compared with the end of
  /// that window, and the result joins the window's metrics. The keyboard and
  /// panel are closed first.
  Future<void> control(Future<void> Function() body);
}

/// The real-IME and panel scenarios.
///
/// Each window is primed by one real open and close outside it; a window that
/// starts with the keyboard up opens it again, also outside.
final imeScenarios = _build();

ScenarioRegistry _build() {
  Scenario scenario(
    String id,
    String window,
    Future<void> Function(ImeContext ctx) body, {
    String? onlyOn,
  }) => Scenario(
    id: id,
    version: 1,
    windows: [window],
    subject: ScenarioSubject.realChat,
    onlyOn: onlyOn,
    run: (ctx) async {
      if (ctx case final ImeContext ime) return body(ime);
      throw StateError('$id needs an ImeContext, got ${ctx.runtimeType}');
    },
  );

  Future<void> primer(ImeContext ctx) async {
    await ctx.openKeyboard();
    await ctx.closeKeyboard();
  }

  Future<void> primerThenUp(ImeContext ctx) async {
    await primer(ctx);
    await ctx.openKeyboard();
  }

  Future<void> opening(ImeContext ctx, KeyboardSeat seat) async {
    await ctx.seat(seat);
    await ctx.measure('open', primer: () => primer(ctx), ctx.openKeyboard);
  }

  return ScenarioRegistry([
    scenario('kbd.open_tail', 'open', (ctx) => opening(ctx, KeyboardSeat.tail)),
    scenario('kbd.close_tail', 'close', (ctx) async {
      await ctx.seat(KeyboardSeat.tail);
      await ctx.measure(
        'close',
        primer: () => primerThenUp(ctx),
        ctx.closeKeyboard,
      );
    }),
    scenario(
      'kbd.open_mid_history',
      'open',
      (ctx) => opening(ctx, KeyboardSeat.midHistory),
    ),
    scenario('kbd.open_mid_fling', 'open', (ctx) async {
      await ctx.seat(KeyboardSeat.midHistory);
      await ctx.measure('open', primer: () => primer(ctx), () async {
        await ctx.fling(_flingDy, _flingTime);
        await ctx.openKeyboard();
      });
      await ctx.control(() async {
        await ctx.seat(KeyboardSeat.midHistory);
        await ctx.fling(_flingDy, _flingTime);
        await ctx.idle(_controlHold);
      });
    }),
    scenario('kbd.open_during_animate', 'open', (ctx) async {
      Future<void> animate() =>
          ctx.animateTo(ctx.history - 1 - _animateMessages, _animateTime);
      await ctx.seat(KeyboardSeat.tail);
      await ctx.measure('open', primer: () => primer(ctx), () async {
        // Concurrent: the keyboard opens while the animation runs.
        await Future.wait([animate(), ctx.openKeyboard()]);
      });
      await ctx.control(() async {
        await ctx.seat(KeyboardSeat.tail);
        await animate();
        await ctx.settle();
      });
    }),
    scenario('kbd.composer_growth', 'open', (ctx) async {
      await ctx.seat(KeyboardSeat.tail);
      await ctx.measure('open', primer: () => primer(ctx), () async {
        await Future.wait([
          ctx.openKeyboard(),
          ctx.growComposer(lines: _growLines, after: _growAfter),
        ]);
      });
    }),
    scenario('panel.open_over_chat', 'open', (ctx) async {
      await ctx.seat(KeyboardSeat.tail);
      await ctx.measure(
        'open',
        primer: () async {
          await ctx.openPanel();
          await ctx.closePanel();
        },
        ctx.openPanel,
      );
    }),
    scenario('panel.keyboard_handoff', 'handoff', (ctx) async {
      await ctx.seat(KeyboardSeat.tail);
      await ctx.measure(
        'handoff',
        primer: () => primerThenUp(ctx),
        ctx.switchToPanel,
      );
    }),
    scenario('kbd.interactive_dismiss', 'dismiss', (ctx) async {
      throw StateError('the interactive dismiss gesture is iOS only');
    }, onlyOn: 'ios'),
  ]);
}
