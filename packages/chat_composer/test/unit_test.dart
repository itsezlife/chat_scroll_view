/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'boundaries_test.dart' as boundaries_test;
import 'input/composer_clipboard_test.dart' as input_composer_clipboard_test;
import 'input/composer_controller_extent_test.dart'
    as composer_controller_extent_test;
import 'input/composer_controller_test.dart' as composer_controller_test;
import 'input/composer_draft_contract_test.dart'
    as composer_draft_contract_test;
import 'input/composer_edit_state_test.dart' as composer_edit_state_test;
import 'input/composer_field_integration_test.dart'
    as composer_field_integration_test;
import 'input/composer_lists_paste_test.dart' as composer_lists_paste_test;
import 'input/composer_mentions_test.dart' as composer_mentions_test;
import 'input/composer_paste_report_test.dart' as composer_paste_report_test;
import 'menu/composer_menu_hints_test.dart' as composer_menu_hints_test;
import 'menu/composer_menu_policy_test.dart' as composer_menu_policy_test;
import 'menu/composer_pointer_menu_items_test.dart'
    as composer_pointer_menu_items_test;
import 'menu/selection_menu_appearance_test.dart'
    as selection_menu_appearance_test;
import 'menu/selection_menu_items_test.dart' as selection_menu_items_test;
import 'menu/selection_menu_overflow_test.dart' as selection_menu_overflow_test;
import 'menu/selection_menu_pages_test.dart' as selection_menu_pages_test;
import 'menu/selection_menu_position_test.dart' as selection_menu_position_test;
import 'menu/selection_menu_swipe_back_test.dart'
    as selection_menu_swipe_back_test;
import 'query/composer_query_test.dart' as composer_query_test;
import 'spec/action_descriptor_test.dart' as action_descriptor_test;
import 'spec/composer_header_test.dart' as composer_header_test;
import 'text/composer_text_controller_atoms_test.dart'
    as composer_text_controller_atoms_test;
import 'text/composer_text_controller_composition_test.dart'
    as composer_text_controller_composition_test;
import 'text/composer_text_controller_draft_test.dart'
    as composer_text_controller_draft_test;
import 'text/composer_text_controller_edit_test.dart'
    as composer_text_controller_edit_test;
import 'text/composer_text_controller_formatting_test.dart'
    as composer_text_controller_formatting_test;
import 'text/composer_text_controller_link_range_test.dart'
    as composer_text_controller_link_range_test;
import 'text/composer_text_controller_lists_test.dart'
    as composer_text_controller_lists_test;
import 'text/composer_text_controller_paint_test.dart'
    as composer_text_controller_paint_test;
import 'text/content_span_builder_test.dart' as content_span_builder_test;
import 'view/composer_actions_test.dart' as composer_actions_test;
import 'view/composer_bottom_fade_test.dart' as composer_bottom_fade_test;
import 'view/composer_caret_reveal_test.dart' as composer_caret_reveal_test;
import 'view/composer_clipboard_test.dart' as view_composer_clipboard_test;
import 'view/composer_field_editable_test.dart' as composer_field_editable_test;
import 'view/composer_formatting_shortcuts_test.dart'
    as composer_formatting_shortcuts_test;
import 'view/composer_golden_test.dart' as composer_golden_test;
import 'view/composer_length_budget_test.dart' as composer_length_budget_test;
import 'view/composer_list_gutter_golden_test.dart'
    as composer_list_gutter_golden_test;
import 'view/composer_lists_field_test.dart' as composer_lists_field_test;
import 'view/composer_menu_labels_test.dart' as composer_menu_labels_test;
import 'view/composer_pointer_menu_golden_test.dart'
    as composer_pointer_menu_golden_test;
import 'view/composer_pointer_menu_test.dart' as composer_pointer_menu_test;
import 'view/composer_selection_highlight_golden_test.dart'
    as composer_selection_highlight_golden_test;
import 'view/composer_selection_menu_fit_test.dart'
    as composer_selection_menu_fit_test;
import 'view/composer_selection_menu_golden_test.dart'
    as composer_selection_menu_golden_test;
import 'view/composer_selection_menu_test.dart' as composer_selection_menu_test;
import 'view/composer_semantics_test.dart' as composer_semantics_test;
import 'view/composer_send_flow_test.dart' as composer_send_flow_test;
import 'view/composer_shortcuts_test.dart' as composer_shortcuts_test;
import 'view/composer_view_test.dart' as composer_view_test;

void main() {
  group('boundaries_test.dart', boundaries_test.main);
  group(
    'input/composer_clipboard_test.dart',
    input_composer_clipboard_test.main,
  );
  group(
    'input/composer_controller_extent_test.dart',
    composer_controller_extent_test.main,
  );
  group('input/composer_controller_test.dart', composer_controller_test.main);
  group(
    'input/composer_draft_contract_test.dart',
    composer_draft_contract_test.main,
  );
  group('input/composer_edit_state_test.dart', composer_edit_state_test.main);
  group(
    'input/composer_field_integration_test.dart',
    composer_field_integration_test.main,
  );
  group('input/composer_lists_paste_test.dart', composer_lists_paste_test.main);
  group('input/composer_mentions_test.dart', composer_mentions_test.main);
  group(
    'input/composer_paste_report_test.dart',
    composer_paste_report_test.main,
  );
  group('menu/composer_menu_hints_test.dart', composer_menu_hints_test.main);
  group('menu/composer_menu_policy_test.dart', composer_menu_policy_test.main);
  group(
    'menu/composer_pointer_menu_items_test.dart',
    composer_pointer_menu_items_test.main,
  );
  group(
    'menu/selection_menu_appearance_test.dart',
    selection_menu_appearance_test.main,
  );
  group('menu/selection_menu_items_test.dart', selection_menu_items_test.main);
  group(
    'menu/selection_menu_overflow_test.dart',
    selection_menu_overflow_test.main,
  );
  group('menu/selection_menu_pages_test.dart', selection_menu_pages_test.main);
  group(
    'menu/selection_menu_position_test.dart',
    selection_menu_position_test.main,
  );
  group(
    'menu/selection_menu_swipe_back_test.dart',
    selection_menu_swipe_back_test.main,
  );
  group('query/composer_query_test.dart', composer_query_test.main);
  group('spec/action_descriptor_test.dart', action_descriptor_test.main);
  group('spec/composer_header_test.dart', composer_header_test.main);
  group(
    'text/composer_text_controller_atoms_test.dart',
    composer_text_controller_atoms_test.main,
  );
  group(
    'text/composer_text_controller_composition_test.dart',
    composer_text_controller_composition_test.main,
  );
  group(
    'text/composer_text_controller_draft_test.dart',
    composer_text_controller_draft_test.main,
  );
  group(
    'text/composer_text_controller_edit_test.dart',
    composer_text_controller_edit_test.main,
  );
  group(
    'text/composer_text_controller_formatting_test.dart',
    composer_text_controller_formatting_test.main,
  );
  group(
    'text/composer_text_controller_link_range_test.dart',
    composer_text_controller_link_range_test.main,
  );
  group(
    'text/composer_text_controller_lists_test.dart',
    composer_text_controller_lists_test.main,
  );
  group(
    'text/composer_text_controller_paint_test.dart',
    composer_text_controller_paint_test.main,
  );
  group('text/content_span_builder_test.dart', content_span_builder_test.main);
  group('view/composer_actions_test.dart', composer_actions_test.main);
  group('view/composer_bottom_fade_test.dart', composer_bottom_fade_test.main);
  group(
    'view/composer_caret_reveal_test.dart',
    composer_caret_reveal_test.main,
  );
  group('view/composer_clipboard_test.dart', view_composer_clipboard_test.main);
  group(
    'view/composer_field_editable_test.dart',
    composer_field_editable_test.main,
  );
  group(
    'view/composer_formatting_shortcuts_test.dart',
    composer_formatting_shortcuts_test.main,
  );
  group('view/composer_golden_test.dart', composer_golden_test.main);
  group(
    'view/composer_length_budget_test.dart',
    composer_length_budget_test.main,
  );
  group(
    'view/composer_list_gutter_golden_test.dart',
    composer_list_gutter_golden_test.main,
  );
  group('view/composer_lists_field_test.dart', composer_lists_field_test.main);
  group('view/composer_menu_labels_test.dart', composer_menu_labels_test.main);
  group(
    'view/composer_selection_highlight_golden_test.dart',
    composer_selection_highlight_golden_test.main,
  );
  group(
    'view/composer_pointer_menu_golden_test.dart',
    composer_pointer_menu_golden_test.main,
  );
  group(
    'view/composer_pointer_menu_test.dart',
    composer_pointer_menu_test.main,
  );
  group(
    'view/composer_selection_menu_fit_test.dart',
    composer_selection_menu_fit_test.main,
  );
  group(
    'view/composer_selection_menu_golden_test.dart',
    composer_selection_menu_golden_test.main,
  );
  group(
    'view/composer_selection_menu_test.dart',
    composer_selection_menu_test.main,
  );
  group('view/composer_semantics_test.dart', composer_semantics_test.main);
  group('view/composer_send_flow_test.dart', composer_send_flow_test.main);
  group('view/composer_shortcuts_test.dart', composer_shortcuts_test.main);
  group('view/composer_view_test.dart', composer_view_test.main);
}
