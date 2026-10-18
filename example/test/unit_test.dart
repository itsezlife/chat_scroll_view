/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'app/app_services_test.dart' as app_services_test;
import 'app/boot_test.dart' as boot_test;
import 'app/listener_errors_test.dart' as listener_errors_test;
import 'backend_chat_data_source_test.dart' as backend_chat_data_source_test;
import 'backend_realtime_reconnect_test.dart'
    as backend_realtime_reconnect_test;
import 'chat_center_band_store_test.dart' as chat_center_band_store_test;
import 'chat_viewport_insets_test.dart' as chat_viewport_insets_test;
import 'common/chat_message_markdown_test.dart' as chat_message_markdown_test;
import 'features/chat/animated_emoji_pack_test.dart'
    as animated_emoji_pack_test;
import 'features/chat/chat_body_host_test.dart' as chat_body_host_test;
import 'features/chat/chat_body_markdown_test.dart' as chat_body_markdown_test;
import 'features/chat/chat_composer_spec_test.dart' as chat_composer_spec_test;
import 'features/chat/chat_copy_test.dart' as chat_copy_test;
import 'features/chat/chat_data_source_bodies_test.dart'
    as chat_data_source_bodies_test;
import 'features/chat/chat_draft_store_test.dart' as chat_draft_store_test;
import 'features/chat/joined_collection_source_test.dart'
    as joined_collection_source_test;
import 'features/chat/large_emoji_test.dart' as large_emoji_test;
import 'features/chat/link_activation_test.dart' as link_activation_test;
import 'glyph_probe_wiring_test.dart' as glyph_probe_wiring_test;
import 'golden/demo_emoji_message_golden_test.dart'
    as demo_emoji_message_golden_test;
import 'golden/demo_widgets_golden_test.dart' as demo_widgets_golden_test;
import 'mapped_value_listenable_test.dart' as mapped_value_listenable_test;
import 'panel_perf/acceptance_runner_test.dart' as acceptance_runner_test;
import 'panel_perf/acceptance_test.dart' as acceptance_test;
import 'panel_perf/frame_metrics_test.dart' as frame_metrics_test;
import 'panel_perf/report_test.dart' as report_test;
import 'pre_ime_back_native_test.dart' as pre_ime_back_native_test;
import 'supabase_chat_data_source_test.dart' as supabase_chat_data_source_test;
import 'theme/demo_chat_theme_test.dart' as demo_chat_theme_test;
import 'theme/demo_markdown_theme_test.dart' as demo_markdown_theme_test;
import 'widgets/chat_composer_menu_test.dart' as chat_composer_menu_test;
import 'widgets/chat_composer_paste_toast_test.dart'
    as chat_composer_paste_toast_test;
import 'widgets/chat_composer_queries_test.dart' as chat_composer_queries_test;
import 'widgets/chat_composer_send_test.dart' as chat_composer_send_test;
import 'widgets/chat_composer_shortcuts_test.dart'
    as chat_composer_shortcuts_test;
import 'widgets/chat_drafts_test.dart' as chat_drafts_test;
import 'widgets/chat_input_set_test.dart' as chat_input_set_test;
import 'widgets/chat_input_wire_test.dart' as chat_input_wire_test;
import 'widgets/chat_link_preview_test.dart' as chat_link_preview_test;
import 'widgets/chat_open_at_last_read_test.dart'
    as chat_open_at_last_read_test;
import 'widgets/chat_scroll_to_bottom_button_test.dart'
    as chat_scroll_to_bottom_button_test;
import 'widgets/chat_selection_test.dart' as chat_selection_test;
import 'widgets/demo_emoji_message_test.dart' as demo_emoji_message_test;
import 'widgets/demo_message_bodies_test.dart' as demo_message_bodies_test;
import 'widgets/demo_message_edit_transition_test.dart'
    as demo_message_edit_transition_test;
import 'widgets/demo_message_markdown_registration_test.dart'
    as demo_message_markdown_registration_test;
import 'widgets/message_menu_test.dart' as message_menu_test;
import 'widgets/notes_dialog_test.dart' as notes_dialog_test;
import 'widgets/panel_keeps_composer_focus_test.dart'
    as panel_keeps_composer_focus_test;
import 'widgets/panel_menu_holds_popup_test.dart'
    as panel_menu_holds_popup_test;
import 'widgets/unread_boundary_background_test.dart'
    as unread_boundary_background_test;
import 'widgets/unread_separator_test.dart' as unread_separator_test;
import 'widgets/widget_chat_screen_bodies_test.dart'
    as widget_chat_screen_bodies_test;
import 'widgets/widget_chat_screen_source_test.dart'
    as widget_chat_screen_source_test;

void main() {
  group('app/app_services_test.dart', app_services_test.main);
  group('app/boot_test.dart', boot_test.main);
  group('app/listener_errors_test.dart', listener_errors_test.main);
  group(
    'backend_chat_data_source_test.dart',
    backend_chat_data_source_test.main,
  );
  group(
    'backend_realtime_reconnect_test.dart',
    backend_realtime_reconnect_test.main,
  );
  group('chat_center_band_store_test.dart', chat_center_band_store_test.main);
  group('chat_viewport_insets_test.dart', chat_viewport_insets_test.main);
  group(
    'common/chat_message_markdown_test.dart',
    chat_message_markdown_test.main,
  );
  group(
    'features/chat/animated_emoji_pack_test.dart',
    animated_emoji_pack_test.main,
  );
  group('features/chat/chat_body_host_test.dart', chat_body_host_test.main);
  group(
    'features/chat/chat_body_markdown_test.dart',
    chat_body_markdown_test.main,
  );
  group(
    'features/chat/chat_composer_spec_test.dart',
    chat_composer_spec_test.main,
  );
  group('features/chat/chat_copy_test.dart', chat_copy_test.main);
  group(
    'features/chat/chat_data_source_bodies_test.dart',
    chat_data_source_bodies_test.main,
  );
  group('features/chat/chat_draft_store_test.dart', chat_draft_store_test.main);
  group(
    'features/chat/joined_collection_source_test.dart',
    joined_collection_source_test.main,
  );
  group('features/chat/large_emoji_test.dart', large_emoji_test.main);
  group('features/chat/link_activation_test.dart', link_activation_test.main);
  group('glyph_probe_wiring_test.dart', glyph_probe_wiring_test.main);
  group(
    'golden/demo_emoji_message_golden_test.dart',
    demo_emoji_message_golden_test.main,
  );
  group('golden/demo_widgets_golden_test.dart', demo_widgets_golden_test.main);
  group('mapped_value_listenable_test.dart', mapped_value_listenable_test.main);
  group('panel_perf/acceptance_runner_test.dart', acceptance_runner_test.main);
  group('panel_perf/acceptance_test.dart', acceptance_test.main);
  group('panel_perf/frame_metrics_test.dart', frame_metrics_test.main);
  group('panel_perf/report_test.dart', report_test.main);
  group('pre_ime_back_native_test.dart', pre_ime_back_native_test.main);
  group(
    'supabase_chat_data_source_test.dart',
    supabase_chat_data_source_test.main,
  );
  group('theme/demo_chat_theme_test.dart', demo_chat_theme_test.main);
  group('theme/demo_markdown_theme_test.dart', demo_markdown_theme_test.main);
  group('widgets/chat_composer_menu_test.dart', chat_composer_menu_test.main);
  group(
    'widgets/chat_composer_paste_toast_test.dart',
    chat_composer_paste_toast_test.main,
  );
  group(
    'widgets/chat_composer_queries_test.dart',
    chat_composer_queries_test.main,
  );
  group('widgets/chat_composer_send_test.dart', chat_composer_send_test.main);
  group(
    'widgets/chat_composer_shortcuts_test.dart',
    chat_composer_shortcuts_test.main,
  );
  group('widgets/chat_drafts_test.dart', chat_drafts_test.main);
  group('widgets/chat_input_set_test.dart', chat_input_set_test.main);
  group('widgets/chat_input_wire_test.dart', chat_input_wire_test.main);
  group('widgets/chat_link_preview_test.dart', chat_link_preview_test.main);
  group(
    'widgets/chat_open_at_last_read_test.dart',
    chat_open_at_last_read_test.main,
  );
  group(
    'widgets/chat_scroll_to_bottom_button_test.dart',
    chat_scroll_to_bottom_button_test.main,
  );
  group('widgets/chat_selection_test.dart', chat_selection_test.main);
  group('widgets/demo_emoji_message_test.dart', demo_emoji_message_test.main);
  group('widgets/demo_message_bodies_test.dart', demo_message_bodies_test.main);
  group(
    'widgets/demo_message_edit_transition_test.dart',
    demo_message_edit_transition_test.main,
  );
  group(
    'widgets/demo_message_markdown_registration_test.dart',
    demo_message_markdown_registration_test.main,
  );
  group('widgets/message_menu_test.dart', message_menu_test.main);
  group('widgets/notes_dialog_test.dart', notes_dialog_test.main);
  group(
    'widgets/panel_keeps_composer_focus_test.dart',
    panel_keeps_composer_focus_test.main,
  );
  group(
    'widgets/panel_menu_holds_popup_test.dart',
    panel_menu_holds_popup_test.main,
  );
  group(
    'widgets/unread_boundary_background_test.dart',
    unread_boundary_background_test.main,
  );
  group('widgets/unread_separator_test.dart', unread_separator_test.main);
  group(
    'widgets/widget_chat_screen_bodies_test.dart',
    widget_chat_screen_bodies_test.main,
  );
  group(
    'widgets/widget_chat_screen_source_test.dart',
    widget_chat_screen_source_test.main,
  );
}
