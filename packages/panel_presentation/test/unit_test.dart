/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'controller/panel_presentation_controller_test.dart'
    as panel_presentation_controller_test;
import 'docked/dock_preference_test.dart' as dock_preference_test;
import 'docked/dock_width_store_test.dart' as dock_width_store_test;
import 'docked/docked_strategy_test.dart' as docked_strategy_test;
import 'docked/docked_style_test.dart' as docked_style_test;
import 'goldens/anchored_popup_golden_test.dart' as anchored_popup_golden_test;
import 'goldens/docked_golden_test.dart' as docked_golden_test;
import 'ime/ime_input_test.dart' as ime_input_test;
import 'keyboard/keyboard_height_store_test.dart' as keyboard_height_store_test;
import 'keyboard/keyboard_replacement_strategy_test.dart'
    as keyboard_replacement_strategy_test;
import 'keyboard/keyboard_slot_test.dart' as keyboard_slot_test;
import 'kind/panel_occupancy_test.dart' as panel_occupancy_test;
import 'policy/panel_presentation_policy_test.dart'
    as panel_presentation_policy_test;
import 'popup/anchored_popup_hover_test.dart' as anchored_popup_hover_test;
import 'popup/anchored_popup_style_test.dart' as anchored_popup_style_test;
import 'popup/anchored_popup_view_test.dart' as anchored_popup_view_test;
import 'testing/manual_panel_clock_test.dart' as manual_panel_clock_test;
import 'view/panel_presentation_view_test.dart' as panel_presentation_view_test;

void main() {
  group(
    'controller/panel_presentation_controller_test.dart',
    panel_presentation_controller_test.main,
  );
  group('docked/dock_preference_test.dart', dock_preference_test.main);
  group('docked/dock_width_store_test.dart', dock_width_store_test.main);
  group('docked/docked_strategy_test.dart', docked_strategy_test.main);
  group('docked/docked_style_test.dart', docked_style_test.main);
  group(
    'goldens/anchored_popup_golden_test.dart',
    anchored_popup_golden_test.main,
  );
  group('goldens/docked_golden_test.dart', docked_golden_test.main);
  group('ime/ime_input_test.dart', ime_input_test.main);
  group(
    'keyboard/keyboard_height_store_test.dart',
    keyboard_height_store_test.main,
  );
  group(
    'keyboard/keyboard_replacement_strategy_test.dart',
    keyboard_replacement_strategy_test.main,
  );
  group('keyboard/keyboard_slot_test.dart', keyboard_slot_test.main);
  group('kind/panel_occupancy_test.dart', panel_occupancy_test.main);
  group(
    'policy/panel_presentation_policy_test.dart',
    panel_presentation_policy_test.main,
  );
  group('popup/anchored_popup_hover_test.dart', anchored_popup_hover_test.main);
  group('popup/anchored_popup_style_test.dart', anchored_popup_style_test.main);
  group('popup/anchored_popup_view_test.dart', anchored_popup_view_test.main);
  group('testing/manual_panel_clock_test.dart', manual_panel_clock_test.main);
  group(
    'view/panel_presentation_view_test.dart',
    panel_presentation_view_test.main,
  );
}
