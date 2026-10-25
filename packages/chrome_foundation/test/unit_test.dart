/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'glass/glass_flat_golden_test.dart' as glass_flat_golden_test;
import 'glass/glass_public_api_test.dart' as glass_public_api_test;
import 'glass/glass_shaders_test.dart' as glass_shaders_test;
import 'glass/glass_source_test.dart' as glass_source_test;
import 'glass/glass_strategy_test.dart' as glass_strategy_test;
import 'glass/glass_surface_route_test.dart' as glass_surface_route_test;
import 'glass/glass_surface_test.dart' as glass_surface_test;
import 'icons/chrome_icon_registry_test.dart' as chrome_icon_registry_test;
import 'icons/chrome_icon_test.dart' as chrome_icon_test;
import 'menu/pointer_menu_aim_test.dart' as pointer_menu_aim_test;
import 'menu/pointer_menu_entry_test.dart' as pointer_menu_entry_test;
import 'menu/pointer_menu_golden_test.dart' as pointer_menu_golden_test;
import 'menu/pointer_menu_placement_test.dart' as pointer_menu_placement_test;
import 'menu/pointer_menu_reveal_test.dart' as pointer_menu_reveal_test;
import 'menu/pointer_menu_test.dart' as pointer_menu_test;
import 'motion/chrome_motion_scope_test.dart' as chrome_motion_scope_test;
import 'motion/chrome_motion_speed_test.dart' as chrome_motion_speed_test;
import 'motion/chrome_motion_test.dart' as chrome_motion_test;
import 'motion/no_literal_durations_test.dart' as no_literal_durations_test;
import 'motion/overshoot_curve_test.dart' as overshoot_curve_test;
import 'motion/pointer_menu_motion_test.dart' as pointer_menu_motion_test;
import 'motion/scale_pressable_test.dart' as scale_pressable_test;
import 'motion/selection_menu_motion_test.dart' as selection_menu_motion_test;
import 'motion/spoiler_motion_test.dart' as spoiler_motion_test;
import 'palette/chrome_contrast_test.dart' as chrome_contrast_test;
import 'palette/chrome_palette_test.dart' as chrome_palette_test;
import 'palette/palette_contrast_test.dart' as palette_contrast_test;
import 'palette/palette_swatch_golden_test.dart' as palette_swatch_golden_test;
import 'strings/chrome_strings_presets_test.dart'
    as chrome_strings_presets_test;
import 'strings/chrome_strings_scope_test.dart' as chrome_strings_scope_test;
import 'theme/chrome_monospace_test.dart' as chrome_monospace_test;
import 'theme/chrome_theme_data_test.dart' as chrome_theme_data_test;
import 'theme/chrome_theme_scope_test.dart' as chrome_theme_scope_test;
import 'tokens/action_tokens_test.dart' as action_tokens_test;
import 'tokens/composer_tokens_test.dart' as composer_tokens_test;
import 'tokens/glass_material_tokens_test.dart' as glass_material_tokens_test;
import 'tokens/panel_tokens_test.dart' as panel_tokens_test;
import 'tokens/placeholder_tokens_test.dart' as placeholder_tokens_test;
import 'tokens/pointer_menu_tokens_test.dart' as pointer_menu_tokens_test;
import 'tokens/selection_menu_tokens_test.dart' as selection_menu_tokens_test;
import 'tokens/spoiler_tokens_test.dart' as spoiler_tokens_test;

void main() {
  group('glass/glass_flat_golden_test.dart', glass_flat_golden_test.main);
  group('glass/glass_public_api_test.dart', glass_public_api_test.main);
  group('glass/glass_shaders_test.dart', glass_shaders_test.main);
  group('glass/glass_source_test.dart', glass_source_test.main);
  group('glass/glass_strategy_test.dart', glass_strategy_test.main);
  group('glass/glass_surface_route_test.dart', glass_surface_route_test.main);
  group('glass/glass_surface_test.dart', glass_surface_test.main);
  group('icons/chrome_icon_registry_test.dart', chrome_icon_registry_test.main);
  group('icons/chrome_icon_test.dart', chrome_icon_test.main);
  group('menu/pointer_menu_aim_test.dart', pointer_menu_aim_test.main);
  group('menu/pointer_menu_test.dart', pointer_menu_test.main);
  group('menu/pointer_menu_golden_test.dart', pointer_menu_golden_test.main);
  group('menu/pointer_menu_entry_test.dart', pointer_menu_entry_test.main);
  group(
    'menu/pointer_menu_placement_test.dart',
    pointer_menu_placement_test.main,
  );
  group('menu/pointer_menu_reveal_test.dart', pointer_menu_reveal_test.main);
  group('motion/chrome_motion_scope_test.dart', chrome_motion_scope_test.main);
  group('motion/chrome_motion_speed_test.dart', chrome_motion_speed_test.main);
  group('motion/chrome_motion_test.dart', chrome_motion_test.main);
  group(
    'motion/no_literal_durations_test.dart',
    no_literal_durations_test.main,
  );
  group('motion/overshoot_curve_test.dart', overshoot_curve_test.main);
  group('motion/pointer_menu_motion_test.dart', pointer_menu_motion_test.main);
  group('motion/scale_pressable_test.dart', scale_pressable_test.main);
  group(
    'motion/selection_menu_motion_test.dart',
    selection_menu_motion_test.main,
  );
  group('motion/spoiler_motion_test.dart', spoiler_motion_test.main);
  group('palette/chrome_contrast_test.dart', chrome_contrast_test.main);
  group('palette/chrome_palette_test.dart', chrome_palette_test.main);
  group('palette/palette_contrast_test.dart', palette_contrast_test.main);
  group(
    'palette/palette_swatch_golden_test.dart',
    palette_swatch_golden_test.main,
  );
  group(
    'strings/chrome_strings_presets_test.dart',
    chrome_strings_presets_test.main,
  );
  group(
    'strings/chrome_strings_scope_test.dart',
    chrome_strings_scope_test.main,
  );
  group('theme/chrome_monospace_test.dart', chrome_monospace_test.main);
  group('theme/chrome_theme_data_test.dart', chrome_theme_data_test.main);
  group('theme/chrome_theme_scope_test.dart', chrome_theme_scope_test.main);
  group('tokens/action_tokens_test.dart', action_tokens_test.main);
  group('tokens/composer_tokens_test.dart', composer_tokens_test.main);
  group(
    'tokens/glass_material_tokens_test.dart',
    glass_material_tokens_test.main,
  );
  group('tokens/panel_tokens_test.dart', panel_tokens_test.main);
  group('tokens/pointer_menu_tokens_test.dart', pointer_menu_tokens_test.main);
  group('tokens/placeholder_tokens_test.dart', placeholder_tokens_test.main);
  group(
    'tokens/selection_menu_tokens_test.dart',
    selection_menu_tokens_test.main,
  );
  group('tokens/spoiler_tokens_test.dart', spoiler_tokens_test.main);
}
