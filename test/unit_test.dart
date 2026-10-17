/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'animate_to_disposition_test.dart' as animate_to_disposition_test;
import 'benchmark/listview_bench_test.dart' as listview_bench_test;
import 'chat_animator_test.dart' as chat_animator_test;
import 'chat_body_linkify_test.dart' as chat_body_linkify_test;
import 'chat_chrome_delegate_test.dart' as chat_chrome_delegate_test;
import 'chat_chunk_fetch_scheduler_test.dart'
    as chat_chunk_fetch_scheduler_test;
import 'chat_floating_header_controller_test.dart'
    as chat_floating_header_controller_test;
import 'chat_message_menu_placement_test.dart'
    as chat_message_menu_placement_test;
import 'chat_mutations_test.dart' as chat_mutations_test;
import 'chat_pre_ime_back_test.dart' as chat_pre_ime_back_test;
import 'chat_range_fetch_test.dart' as chat_range_fetch_test;
import 'chat_scroll_activity_clock_test.dart'
    as chat_scroll_activity_clock_test;
import 'chat_scroll_chunk_test.dart' as chat_scroll_chunk_test;
import 'chat_scroll_motion_test.dart' as chat_scroll_motion_test;
import 'chat_scroll_physics_test.dart' as chat_scroll_physics_test;
import 'chat_sender_run_layout_test.dart' as chat_sender_run_layout_test;
import 'chat_stretch_overscroll_test.dart' as chat_stretch_overscroll_test;
import 'widgets/chat_absent_build_test.dart' as chat_absent_build_test;
import 'widgets/chat_animate_path_test.dart' as chat_animate_path_test;
import 'widgets/chat_api_test.dart' as chat_api_test;
import 'widgets/chat_bottom_padding_compensation_test.dart'
    as chat_bottom_padding_compensation_test;
import 'widgets/chat_bubble_metrics_test.dart' as chat_bubble_metrics_test;
import 'widgets/chat_center_band_test.dart' as chat_center_band_test;
import 'widgets/chat_code_block_painter_test.dart'
    as chat_code_block_painter_test;
import 'widgets/chat_controller_test.dart' as chat_controller_test;
import 'widgets/chat_date_separator_test.dart' as chat_date_separator_test;
import 'widgets/chat_dispose_during_animate_test.dart'
    as chat_dispose_during_animate_test;
import 'widgets/chat_follow_tail_test.dart' as chat_follow_tail_test;
import 'widgets/chat_gap_test.dart' as chat_gap_test;
import 'widgets/chat_ghost_selected_color_test.dart'
    as chat_ghost_selected_color_test;
import 'widgets/chat_highlight_test.dart' as chat_highlight_test;
import 'widgets/chat_idle_message_tap_test.dart' as chat_idle_message_tap_test;
import 'widgets/chat_invalidate_test.dart' as chat_invalidate_test;
import 'widgets/chat_jump_to_tail_test.dart' as chat_jump_to_tail_test;
import 'widgets/chat_keyboard_test.dart' as chat_keyboard_test;
import 'widgets/chat_lazy_pagination_test.dart' as chat_lazy_pagination_test;
import 'widgets/chat_lifecycle_test.dart' as chat_lifecycle_test;
import 'widgets/chat_markdown_autoscroll_test.dart'
    as chat_markdown_autoscroll_test;
import 'widgets/chat_markdown_body_inline_hit_test.dart'
    as chat_markdown_body_inline_hit_test;
import 'widgets/chat_message_body_layout_test.dart'
    as chat_message_body_layout_test;
import 'widgets/chat_message_body_test.dart' as chat_message_body_test;
import 'widgets/chat_message_change_diag_test.dart'
    as chat_message_change_diag_test;
import 'widgets/chat_message_change_params_test.dart'
    as chat_message_change_params_test;
import 'widgets/chat_message_change_transition_test.dart'
    as chat_message_change_transition_test;
import 'widgets/chat_message_menu_request_test.dart'
    as chat_message_menu_request_test;
import 'widgets/chat_message_menu_test.dart' as chat_message_menu_test;
import 'widgets/chat_message_theme_test.dart' as chat_message_theme_test;
import 'widgets/chat_mobile_text_chrome_test.dart'
    as chat_mobile_text_chrome_test;
import 'widgets/chat_mount_scroll_magnet_test.dart'
    as chat_mount_scroll_magnet_test;
import 'widgets/chat_navigation_alignment_test.dart'
    as chat_navigation_alignment_test;
import 'widgets/chat_overscroll_test.dart' as chat_overscroll_test;
import 'widgets/chat_row_chrome_test.dart' as chat_row_chrome_test;
import 'widgets/chat_rtl_test.dart' as chat_rtl_test;
import 'widgets/chat_scroll_physics_test.dart'
    as widgets_chat_scroll_physics_test;
import 'widgets/chat_scroll_theme_test.dart' as chat_scroll_theme_test;
import 'widgets/chat_scrollable_table_selection_gate_test.dart'
    as chat_scrollable_table_selection_gate_test;
import 'widgets/chat_scrollbar_fetch_test.dart' as chat_scrollbar_fetch_test;
import 'widgets/chat_scrollbar_grab_test.dart' as chat_scrollbar_grab_test;
import 'widgets/chat_scrollbar_host_test.dart' as chat_scrollbar_host_test;
import 'widgets/chat_scrollbar_presets_test.dart'
    as chat_scrollbar_presets_test;
import 'widgets/chat_scrollbar_test.dart' as chat_scrollbar_test;
import 'widgets/chat_scrollbar_theme_test.dart' as chat_scrollbar_theme_test;
import 'widgets/chat_scrollbar_visibility_test.dart'
    as chat_scrollbar_visibility_test;
import 'widgets/chat_select_span_test.dart' as chat_select_span_test;
import 'widgets/chat_selection_allowed_test.dart'
    as chat_selection_allowed_test;
import 'widgets/chat_selection_cap_test.dart' as chat_selection_cap_test;
import 'widgets/chat_selection_chrome_test.dart' as chat_selection_chrome_test;
import 'widgets/chat_selection_pointer_test.dart'
    as chat_selection_pointer_test;
import 'widgets/chat_selection_text_test.dart' as chat_selection_text_test;
import 'widgets/chat_send_scroll_test.dart' as chat_send_scroll_test;
import 'widgets/chat_sender_run_test.dart' as chat_sender_run_test;
import 'widgets/chat_smooth_contour_test.dart' as chat_smooth_contour_test;
import 'widgets/chat_span_auto_scroll_test.dart' as chat_span_auto_scroll_test;
import 'widgets/chat_span_feedback_test.dart' as chat_span_feedback_test;
import 'widgets/chat_stitch_animate_test.dart' as chat_stitch_animate_test;
import 'widgets/chat_tap_dismiss_toggle_regression_test.dart'
    as chat_tap_dismiss_toggle_regression_test;
import 'widgets/chat_tap_highlight_test.dart' as chat_tap_highlight_test;
import 'widgets/chat_tap_highlight_text_selection_test.dart'
    as chat_tap_highlight_text_selection_test;
import 'widgets/chat_unread_separator_test.dart' as chat_unread_separator_test;
import 'widgets/chat_unselect_span_test.dart' as chat_unselect_span_test;
import 'widgets/chat_viewport_stable_delete_test.dart'
    as chat_viewport_stable_delete_test;
import 'widgets/chat_widgets_bench_test.dart' as chat_widgets_bench_test;
import 'widgets/chat_widgets_test.dart' as chat_widgets_test;
import 'widgets/vs_listview_bench_test.dart' as vs_listview_bench_test;

void main() {
  group('animate_to_disposition_test.dart', animate_to_disposition_test.main);
  group('benchmark/listview_bench_test.dart', listview_bench_test.main);
  group('chat_animator_test.dart', chat_animator_test.main);
  group('chat_body_linkify_test.dart', chat_body_linkify_test.main);
  group('chat_chrome_delegate_test.dart', chat_chrome_delegate_test.main);
  group(
    'chat_chunk_fetch_scheduler_test.dart',
    chat_chunk_fetch_scheduler_test.main,
  );
  group(
    'chat_floating_header_controller_test.dart',
    chat_floating_header_controller_test.main,
  );
  group(
    'chat_message_menu_placement_test.dart',
    chat_message_menu_placement_test.main,
  );
  group('chat_mutations_test.dart', chat_mutations_test.main);
  group('chat_pre_ime_back_test.dart', chat_pre_ime_back_test.main);
  group('chat_range_fetch_test.dart', chat_range_fetch_test.main);
  group(
    'chat_scroll_activity_clock_test.dart',
    chat_scroll_activity_clock_test.main,
  );
  group('chat_scroll_chunk_test.dart', chat_scroll_chunk_test.main);
  group('chat_scroll_motion_test.dart', chat_scroll_motion_test.main);
  group('chat_scroll_physics_test.dart', chat_scroll_physics_test.main);
  group('chat_sender_run_layout_test.dart', chat_sender_run_layout_test.main);
  group('chat_stretch_overscroll_test.dart', chat_stretch_overscroll_test.main);
  group('widgets/chat_absent_build_test.dart', chat_absent_build_test.main);
  group('widgets/chat_animate_path_test.dart', chat_animate_path_test.main);
  group('widgets/chat_api_test.dart', chat_api_test.main);
  group(
    'widgets/chat_bottom_padding_compensation_test.dart',
    chat_bottom_padding_compensation_test.main,
  );
  group('widgets/chat_bubble_metrics_test.dart', chat_bubble_metrics_test.main);
  group('widgets/chat_center_band_test.dart', chat_center_band_test.main);
  group(
    'widgets/chat_code_block_painter_test.dart',
    chat_code_block_painter_test.main,
  );
  group('widgets/chat_controller_test.dart', chat_controller_test.main);
  group('widgets/chat_date_separator_test.dart', chat_date_separator_test.main);
  group(
    'widgets/chat_dispose_during_animate_test.dart',
    chat_dispose_during_animate_test.main,
  );
  group('widgets/chat_follow_tail_test.dart', chat_follow_tail_test.main);
  group('widgets/chat_gap_test.dart', chat_gap_test.main);
  group(
    'widgets/chat_ghost_selected_color_test.dart',
    chat_ghost_selected_color_test.main,
  );
  group('widgets/chat_highlight_test.dart', chat_highlight_test.main);
  group(
    'widgets/chat_idle_message_tap_test.dart',
    chat_idle_message_tap_test.main,
  );
  group('widgets/chat_invalidate_test.dart', chat_invalidate_test.main);
  group('widgets/chat_jump_to_tail_test.dart', chat_jump_to_tail_test.main);
  group('widgets/chat_keyboard_test.dart', chat_keyboard_test.main);
  group(
    'widgets/chat_lazy_pagination_test.dart',
    chat_lazy_pagination_test.main,
  );
  group('widgets/chat_lifecycle_test.dart', chat_lifecycle_test.main);
  group(
    'widgets/chat_markdown_autoscroll_test.dart',
    chat_markdown_autoscroll_test.main,
  );
  group(
    'widgets/chat_markdown_body_inline_hit_test.dart',
    chat_markdown_body_inline_hit_test.main,
  );
  group(
    'widgets/chat_message_body_layout_test.dart',
    chat_message_body_layout_test.main,
  );
  group('widgets/chat_message_body_test.dart', chat_message_body_test.main);
  group(
    'widgets/chat_message_change_diag_test.dart',
    chat_message_change_diag_test.main,
  );
  group(
    'widgets/chat_message_change_params_test.dart',
    chat_message_change_params_test.main,
  );
  group(
    'widgets/chat_message_change_transition_test.dart',
    chat_message_change_transition_test.main,
  );
  group(
    'widgets/chat_message_menu_request_test.dart',
    chat_message_menu_request_test.main,
  );
  group('widgets/chat_message_menu_test.dart', chat_message_menu_test.main);
  group('widgets/chat_message_theme_test.dart', chat_message_theme_test.main);
  group(
    'widgets/chat_mobile_text_chrome_test.dart',
    chat_mobile_text_chrome_test.main,
  );
  group(
    'widgets/chat_mount_scroll_magnet_test.dart',
    chat_mount_scroll_magnet_test.main,
  );
  group(
    'widgets/chat_navigation_alignment_test.dart',
    chat_navigation_alignment_test.main,
  );
  group('widgets/chat_overscroll_test.dart', chat_overscroll_test.main);
  group('widgets/chat_row_chrome_test.dart', chat_row_chrome_test.main);
  group('widgets/chat_rtl_test.dart', chat_rtl_test.main);
  group(
    'widgets/chat_scroll_physics_test.dart',
    widgets_chat_scroll_physics_test.main,
  );
  group('widgets/chat_scroll_theme_test.dart', chat_scroll_theme_test.main);
  group(
    'widgets/chat_scrollable_table_selection_gate_test.dart',
    chat_scrollable_table_selection_gate_test.main,
  );
  group(
    'widgets/chat_scrollbar_fetch_test.dart',
    chat_scrollbar_fetch_test.main,
  );
  group('widgets/chat_scrollbar_grab_test.dart', chat_scrollbar_grab_test.main);
  group('widgets/chat_scrollbar_host_test.dart', chat_scrollbar_host_test.main);
  group(
    'widgets/chat_scrollbar_presets_test.dart',
    chat_scrollbar_presets_test.main,
  );
  group('widgets/chat_scrollbar_test.dart', chat_scrollbar_test.main);
  group(
    'widgets/chat_scrollbar_theme_test.dart',
    chat_scrollbar_theme_test.main,
  );
  group(
    'widgets/chat_scrollbar_visibility_test.dart',
    chat_scrollbar_visibility_test.main,
  );
  group('widgets/chat_select_span_test.dart', chat_select_span_test.main);
  group(
    'widgets/chat_selection_allowed_test.dart',
    chat_selection_allowed_test.main,
  );
  group('widgets/chat_selection_cap_test.dart', chat_selection_cap_test.main);
  group(
    'widgets/chat_selection_chrome_test.dart',
    chat_selection_chrome_test.main,
  );
  group(
    'widgets/chat_selection_pointer_test.dart',
    chat_selection_pointer_test.main,
  );
  group('widgets/chat_selection_text_test.dart', chat_selection_text_test.main);
  group('widgets/chat_send_scroll_test.dart', chat_send_scroll_test.main);
  group('widgets/chat_sender_run_test.dart', chat_sender_run_test.main);
  group('widgets/chat_smooth_contour_test.dart', chat_smooth_contour_test.main);
  group(
    'widgets/chat_span_auto_scroll_test.dart',
    chat_span_auto_scroll_test.main,
  );
  group('widgets/chat_span_feedback_test.dart', chat_span_feedback_test.main);
  group('widgets/chat_stitch_animate_test.dart', chat_stitch_animate_test.main);
  group(
    'widgets/chat_tap_dismiss_toggle_regression_test.dart',
    chat_tap_dismiss_toggle_regression_test.main,
  );
  group('widgets/chat_tap_highlight_test.dart', chat_tap_highlight_test.main);
  group(
    'widgets/chat_tap_highlight_text_selection_test.dart',
    chat_tap_highlight_text_selection_test.main,
  );
  group(
    'widgets/chat_unread_separator_test.dart',
    chat_unread_separator_test.main,
  );
  group('widgets/chat_unselect_span_test.dart', chat_unselect_span_test.main);
  group(
    'widgets/chat_viewport_stable_delete_test.dart',
    chat_viewport_stable_delete_test.main,
  );
  group('widgets/chat_widgets_bench_test.dart', chat_widgets_bench_test.main);
  group('widgets/chat_widgets_test.dart', chat_widgets_test.main);
  group('widgets/vs_listview_bench_test.dart', vs_listview_bench_test.main);
}
