/// How the panel is presented: sealed presentation kinds (keyboard
/// replacement, anchored popup, docked), the pure-Dart mobile and desktop
/// policy that picks one, the presentation controller that owns visibility
/// and wraps the panel shell, published occupancy and the IME input port.
///
/// Depends on `panel_shell`, `chrome_foundation` and `content_model` only; it
/// never sees page content or data payloads.
library;

export 'src/controller/panel_presentation_controller.dart';
export 'src/ime/ime_input_port.dart';
export 'src/ime/ime_sample.dart';
export 'src/keyboard/keyboard_height_store.dart';
export 'src/keyboard/keyboard_nav_bar_fade.dart';
export 'src/keyboard/keyboard_replacement_strategy.dart';
export 'src/keyboard/keyboard_replacement_tuning.dart';
export 'src/keyboard/keyboard_slot.dart';
export 'src/keyboard/keyboard_slot_state.dart';
export 'src/kind/panel_occupancy.dart';
export 'src/kind/panel_presentation.dart';
export 'src/kind/panel_visibility.dart';
export 'src/policy/panel_os_family.dart';
export 'src/policy/panel_presentation_policy.dart';
export 'src/policy/panel_window.dart';
export 'src/strategy/panel_presentation_strategy.dart';
export 'src/time/panel_clock.dart';
export 'src/view/panel_presentation_view.dart';
