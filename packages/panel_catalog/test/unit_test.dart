/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'adaptive_grid_viewport_test.dart' as adaptive_grid_viewport_test;
import 'benchmark/vs_supersliver_bench_test.dart' as vs_supersliver_bench_test;
import 'catalog_paragraph_cache_test.dart' as catalog_paragraph_cache_test;
import 'catalog_scroll_position_contract_test.dart'
    as catalog_scroll_position_contract_test;
import 'current_section_test.dart' as current_section_test;
import 'data/catalog_snapshot_test.dart' as catalog_snapshot_test;
import 'goldens/placeholders_golden_test.dart' as placeholders_golden_test;
import 'goldens/rtl_golden_test.dart' as rtl_golden_test;
import 'goldens/section_states_golden_test.dart' as section_states_golden_test;
import 'model/catalog_leaf_test.dart' as catalog_leaf_test;
import 'model/catalog_section_test.dart' as catalog_section_test;
import 'panel_catalog_asset_binding_test.dart'
    as panel_catalog_asset_binding_test;
import 'panel_catalog_baked_sprites_test.dart'
    as panel_catalog_baked_sprites_test;
import 'panel_catalog_controller_test.dart' as panel_catalog_controller_test;
import 'panel_catalog_cursor_test.dart' as panel_catalog_cursor_test;
import 'panel_catalog_focus_test.dart' as panel_catalog_focus_test;
import 'panel_catalog_hover_test.dart' as panel_catalog_hover_test;
import 'panel_catalog_pointer_seams_test.dart'
    as panel_catalog_pointer_seams_test;
import 'panel_catalog_scroll_events_test.dart'
    as panel_catalog_scroll_events_test;
import 'panel_catalog_scroll_hardening_test.dart'
    as panel_catalog_scroll_hardening_test;
import 'panel_catalog_semantics_test.dart' as panel_catalog_semantics_test;
import 'panel_catalog_theme_test.dart' as panel_catalog_theme_test;
import 'panel_catalog_viewport_test.dart' as panel_catalog_viewport_test;
import 'section_actions_test.dart' as section_actions_test;
import 'section_layout_viewport_test.dart' as section_layout_viewport_test;
import 'section_near_viewport_test.dart' as section_near_viewport_test;
import 'section_states_test.dart' as section_states_test;
import 'viewport/catalog_focus_navigation_test.dart'
    as catalog_focus_navigation_test;
import 'viewport/section_direction_projection_test.dart'
    as section_direction_projection_test;
import 'viewport/section_layout_projection_test.dart'
    as section_layout_projection_test;
import 'viewport_direction_test.dart' as viewport_direction_test;

void main() {
  group('adaptive_grid_viewport_test.dart', adaptive_grid_viewport_test.main);
  group(
    'benchmark/vs_supersliver_bench_test.dart',
    vs_supersliver_bench_test.main,
  );
  group('catalog_paragraph_cache_test.dart', catalog_paragraph_cache_test.main);
  group(
    'catalog_scroll_position_contract_test.dart',
    catalog_scroll_position_contract_test.main,
  );
  group('current_section_test.dart', current_section_test.main);
  group('data/catalog_snapshot_test.dart', catalog_snapshot_test.main);
  group('goldens/placeholders_golden_test.dart', placeholders_golden_test.main);
  group('goldens/rtl_golden_test.dart', rtl_golden_test.main);
  group(
    'goldens/section_states_golden_test.dart',
    section_states_golden_test.main,
  );
  group('model/catalog_leaf_test.dart', catalog_leaf_test.main);
  group('model/catalog_section_test.dart', catalog_section_test.main);
  group(
    'panel_catalog_asset_binding_test.dart',
    panel_catalog_asset_binding_test.main,
  );
  group(
    'panel_catalog_baked_sprites_test.dart',
    panel_catalog_baked_sprites_test.main,
  );
  group(
    'panel_catalog_controller_test.dart',
    panel_catalog_controller_test.main,
  );
  group('panel_catalog_cursor_test.dart', panel_catalog_cursor_test.main);
  group('panel_catalog_focus_test.dart', panel_catalog_focus_test.main);
  group('panel_catalog_hover_test.dart', panel_catalog_hover_test.main);
  group(
    'panel_catalog_pointer_seams_test.dart',
    panel_catalog_pointer_seams_test.main,
  );
  group(
    'panel_catalog_scroll_events_test.dart',
    panel_catalog_scroll_events_test.main,
  );
  group(
    'panel_catalog_scroll_hardening_test.dart',
    panel_catalog_scroll_hardening_test.main,
  );
  group('panel_catalog_semantics_test.dart', panel_catalog_semantics_test.main);
  group('panel_catalog_theme_test.dart', panel_catalog_theme_test.main);
  group('panel_catalog_viewport_test.dart', panel_catalog_viewport_test.main);
  group('section_actions_test.dart', section_actions_test.main);
  group('section_layout_viewport_test.dart', section_layout_viewport_test.main);
  group('section_near_viewport_test.dart', section_near_viewport_test.main);
  group('section_states_test.dart', section_states_test.main);
  group(
    'viewport/catalog_focus_navigation_test.dart',
    catalog_focus_navigation_test.main,
  );
  group(
    'viewport/section_direction_projection_test.dart',
    section_direction_projection_test.main,
  );
  group(
    'viewport/section_layout_projection_test.dart',
    section_layout_projection_test.main,
  );
  group('viewport_direction_test.dart', viewport_direction_test.main);
}
