/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'box/confirm_box_test.dart' as confirm_box_test;
import 'files/files_page_test.dart' as files_page_test;
import 'gallery/gallery_captures_test.dart' as gallery_captures_test;
import 'gallery/gallery_page_test.dart' as gallery_page_test;
import 'header/attach_selection_header_controller_test.dart'
    as attach_selection_header_controller_test;
import 'header/gallery_selection_header_test.dart'
    as gallery_selection_header_test;
import 'limits/derive_attach_limits_test.dart' as derive_attach_limits_test;
import 'page/attach_bar_inset_test.dart' as attach_bar_inset_test;
import 'page/attach_page_test.dart' as attach_page_test;
import 'page/attach_tab_bar_test.dart' as attach_tab_bar_test;
import 'panel/attach_panel_test.dart' as attach_panel_test;
import 'policy/attach_sheet_policy_test.dart' as attach_sheet_policy_test;
import 'sheet/attach_sheet_android_test.dart' as attach_sheet_android_test;
import 'sheet/attach_sheet_glass_test.dart' as attach_sheet_glass_test;
import 'sheet/attach_sheet_golden_test.dart' as attach_sheet_golden_test;
import 'sheet/attach_sheet_ios_test.dart' as attach_sheet_ios_test;
import 'sheet/attach_sheet_morph_test.dart' as attach_sheet_morph_test;
import 'sheet/attach_sheet_text_test.dart' as attach_sheet_text_test;

void main() {
  group('box/confirm_box_test.dart', confirm_box_test.main);
  group('files/files_page_test.dart', files_page_test.main);
  group('gallery/gallery_captures_test.dart', gallery_captures_test.main);
  group('gallery/gallery_page_test.dart', gallery_page_test.main);
  group(
    'header/attach_selection_header_controller_test.dart',
    attach_selection_header_controller_test.main,
  );
  group(
    'header/gallery_selection_header_test.dart',
    gallery_selection_header_test.main,
  );
  group(
    'limits/derive_attach_limits_test.dart',
    derive_attach_limits_test.main,
  );
  group('page/attach_bar_inset_test.dart', attach_bar_inset_test.main);
  group('page/attach_page_test.dart', attach_page_test.main);
  group('page/attach_tab_bar_test.dart', attach_tab_bar_test.main);
  group('panel/attach_panel_test.dart', attach_panel_test.main);
  group('policy/attach_sheet_policy_test.dart', attach_sheet_policy_test.main);
  group('sheet/attach_sheet_android_test.dart', attach_sheet_android_test.main);
  group('sheet/attach_sheet_glass_test.dart', attach_sheet_glass_test.main);
  group('sheet/attach_sheet_golden_test.dart', attach_sheet_golden_test.main);
  group('sheet/attach_sheet_ios_test.dart', attach_sheet_ios_test.main);
  group('sheet/attach_sheet_morph_test.dart', attach_sheet_morph_test.main);
  group('sheet/attach_sheet_text_test.dart', attach_sheet_text_test.main);
}
