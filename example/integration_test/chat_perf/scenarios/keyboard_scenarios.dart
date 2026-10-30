/// Synthetic keyboard-inset scenarios on the real chat screen (spec 7.3).
///
/// Pure Dart: they speak only to a [KeyboardContext]. The context drives a
/// deterministic inset curve into the host's soft-keyboard port frame by frame
/// and records the per-frame trace the ramp metrics are computed from.
library;

import '../keyboard_ramp.dart';
import '../registry.dart';

/// Where in the history a scenario starts.
enum KeyboardSeat {
  /// At the newest message.
  tail,

  /// In the middle of a long history, away from both ends.
  midHistory,
}

/// What a keyboard scenario sees, on top of the generic [ScenarioContext].
abstract interface class KeyboardContext implements ScenarioContext {
  /// Moves the viewport to [seat] and settles, outside any window.
  Future<void> seat(KeyboardSeat seat);

  /// Drives the host's keyboard to [curve] (scaled by the profile's height),
  /// one value per frame, in real time. Inside a window the per-frame trace
  /// is kept and its ramp metrics join the window's.
  Future<void> ramp(InsetCurve curve);

  /// A paced fling that ends at the release; the scroll carries on.
  Future<void> fling();

  /// Pumps frames for [duration] in real time.
  Future<void> hold(Duration duration);

  /// Taps the composer's panel toggle, so the panel takes the keyboard's slot,
  /// and runs the closing [curve] beside it (the keyboard-to-panel hand-off).
  Future<void> handOffToPanel(InsetCurve curve);

  /// Runs [body] as the control of the last measured window: the same script
  /// without the inset change, not measured. Its end is compared with the end
  /// of that window, and the result joins the window's metrics.
  Future<void> control(Future<void> Function() body);
}

/// The scenarios of the keyboard family under [profile].
///
/// Each scenario's window is primed by a low-amplitude open and close of the
/// same curve, outside the window; a window that starts with the keyboard up
/// then opens it in full, also outside.
ScenarioRegistry buildKeyboardScenarios(InsetCurveProfile profile) {
  Scenario scenario(
    String id,
    String window,
    Future<void> Function(KeyboardContext ctx) body,
  ) => Scenario(
    id: id,
    version: 1,
    windows: [window],
    run: (ctx) async {
      if (ctx case final KeyboardContext kbd) return body(kbd);
      throw StateError('$id needs a KeyboardContext, got ${ctx.runtimeType}');
    },
  );

  Future<void> primer(KeyboardContext ctx) async {
    await ctx.ramp(profile.open.scaled(0.3));
    await ctx.ramp(profile.close.scaled(0.3));
  }

  // A window that starts with the keyboard up is primed, then opened in full
  // outside the window, so it starts from the settled keyboard.
  Future<void> primerThenUp(KeyboardContext ctx) async {
    await primer(ctx);
    await ctx.ramp(profile.open);
  }

  Future<void> opening(KeyboardContext ctx, KeyboardSeat seat) async {
    await ctx.seat(seat);
    await ctx.measure(
      'open',
      primer: () => primer(ctx),
      () => ctx.ramp(profile.open),
    );
  }

  return ScenarioRegistry([
    scenario(
      'kbd.synthetic_open_tail',
      'open',
      (ctx) => opening(ctx, KeyboardSeat.tail),
    ),
    scenario('kbd.synthetic_close_tail', 'close', (ctx) async {
      await ctx.seat(KeyboardSeat.tail);
      await ctx.measure(
        'close',
        primer: () => primerThenUp(ctx),
        () => ctx.ramp(profile.close),
      );
    }),
    scenario(
      'kbd.synthetic_open_mid_history',
      'open',
      (ctx) => opening(ctx, KeyboardSeat.midHistory),
    ),
    scenario('kbd.synthetic_open_mid_fling', 'open', (ctx) async {
      await ctx.seat(KeyboardSeat.midHistory);
      await ctx.measure('open', primer: () => primer(ctx), () async {
        await ctx.fling();
        await ctx.ramp(profile.open);
      });
      // The same fling, held as long, with no inset change.
      await ctx.control(() async {
        await ctx.seat(KeyboardSeat.midHistory);
        await ctx.fling();
        await ctx.hold(Duration(milliseconds: profile.open.durationMs.ceil()));
      });
    }),
    scenario('kbd.synthetic_handoff', 'handoff', (ctx) async {
      await ctx.seat(KeyboardSeat.tail);
      await ctx.measure(
        'handoff',
        primer: () => primerThenUp(ctx),
        () => ctx.handOffToPanel(profile.close),
      );
    }),
  ]);
}

/// The family under the `android_ramp` profile.
final keyboardScenarios = buildKeyboardScenarios(InsetCurveProfile.androidRamp);
