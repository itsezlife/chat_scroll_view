/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'assets/page_assets_test.dart' as page_assets_test;
import 'atlas/glyph_atlas_host_test.dart' as glyph_atlas_host_test;
import 'atlas/glyph_plan_test.dart' as glyph_plan_test;
import 'bake/bake_activity_port_contract_test.dart'
    as bake_activity_port_contract_test;
import 'bake/catalog_bake_forwarder_test.dart' as catalog_bake_forwarder_test;
import 'bake/glyph_atlas_bake_port_test.dart' as glyph_atlas_bake_port_test;
import 'emoji/emoji_category_strip_test.dart' as emoji_category_strip_test;
import 'emoji/emoji_page_desktop_test.dart' as emoji_page_desktop_test;
import 'emoji/emoji_page_in_shell_test.dart' as emoji_page_in_shell_test;
import 'emoji/emoji_page_pointer_test.dart' as emoji_page_pointer_test;
import 'emoji/emoji_page_policy_test.dart' as emoji_page_policy_test;
import 'emoji/emoji_page_test.dart' as emoji_page_test;
import 'emoji/emoji_page_tooltip_test.dart' as emoji_page_tooltip_test;
import 'emoji/emoji_tab_icons_test.dart' as emoji_tab_icons_test;
import 'emoji/emoji_tone_picker_touch_test.dart'
    as emoji_tone_picker_touch_test;
import 'emoji/emoji_variant_picker_ink_test.dart'
    as emoji_variant_picker_ink_test;
import 'emoji/emoji_variant_picker_layout_test.dart'
    as emoji_variant_picker_layout_test;
import 'goldens/emoji_page_golden_test.dart' as emoji_page_golden_test;
import 'menu/catalog_context_menu_test.dart' as catalog_context_menu_test;
import 'page/catalog_page_contents_change_test.dart'
    as catalog_page_contents_change_test;
import 'page/catalog_page_in_shell_test.dart' as catalog_page_in_shell_test;
import 'page/catalog_page_model_test.dart' as catalog_page_model_test;
import 'page/catalog_page_sticky_test.dart' as catalog_page_sticky_test;
import 'page/catalog_page_test.dart' as catalog_page_test;
import 'page/catalog_sticky_header_test.dart' as catalog_sticky_header_test;
import 'scroll/page_scroll_reporter_test.dart' as page_scroll_reporter_test;
import 'snapshot/catalog_snapshot_builder_test.dart'
    as catalog_snapshot_builder_test;
import 'theme/chrome_catalog_theme_test.dart' as chrome_catalog_theme_test;

void main() {
  group('assets/page_assets_test.dart', page_assets_test.main);
  group('atlas/glyph_atlas_host_test.dart', glyph_atlas_host_test.main);
  group('atlas/glyph_plan_test.dart', glyph_plan_test.main);
  group(
    'bake/bake_activity_port_contract_test.dart',
    bake_activity_port_contract_test.main,
  );
  group(
    'bake/catalog_bake_forwarder_test.dart',
    catalog_bake_forwarder_test.main,
  );
  group(
    'bake/glyph_atlas_bake_port_test.dart',
    glyph_atlas_bake_port_test.main,
  );
  group('emoji/emoji_category_strip_test.dart', emoji_category_strip_test.main);
  group('emoji/emoji_page_desktop_test.dart', emoji_page_desktop_test.main);
  group('emoji/emoji_page_in_shell_test.dart', emoji_page_in_shell_test.main);
  group('emoji/emoji_page_pointer_test.dart', emoji_page_pointer_test.main);
  group('emoji/emoji_page_policy_test.dart', emoji_page_policy_test.main);
  group('emoji/emoji_page_tooltip_test.dart', emoji_page_tooltip_test.main);
  group('emoji/emoji_page_test.dart', emoji_page_test.main);
  group('emoji/emoji_tab_icons_test.dart', emoji_tab_icons_test.main);
  group(
    'emoji/emoji_tone_picker_touch_test.dart',
    emoji_tone_picker_touch_test.main,
  );
  group(
    'emoji/emoji_variant_picker_ink_test.dart',
    emoji_variant_picker_ink_test.main,
  );
  group(
    'emoji/emoji_variant_picker_layout_test.dart',
    emoji_variant_picker_layout_test.main,
  );
  group('goldens/emoji_page_golden_test.dart', emoji_page_golden_test.main);
  group('menu/catalog_context_menu_test.dart', catalog_context_menu_test.main);
  group(
    'page/catalog_page_contents_change_test.dart',
    catalog_page_contents_change_test.main,
  );
  group(
    'page/catalog_page_in_shell_test.dart',
    catalog_page_in_shell_test.main,
  );
  group('page/catalog_page_model_test.dart', catalog_page_model_test.main);
  group('page/catalog_page_sticky_test.dart', catalog_page_sticky_test.main);
  group('page/catalog_page_test.dart', catalog_page_test.main);
  group(
    'page/catalog_sticky_header_test.dart',
    catalog_sticky_header_test.main,
  );
  group(
    'scroll/page_scroll_reporter_test.dart',
    page_scroll_reporter_test.main,
  );
  group(
    'snapshot/catalog_snapshot_builder_test.dart',
    catalog_snapshot_builder_test.main,
  );
  group('theme/chrome_catalog_theme_test.dart', chrome_catalog_theme_test.main);
}
