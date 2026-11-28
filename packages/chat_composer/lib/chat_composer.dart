/// A slot-based chat composer: a host-built `ComposerSpec` describes the
/// header, panel and actions; `ComposerView` lays them out in a glass island
/// and publishes its extent. Beside it sit the input-only controller, the
/// entity-aware text controller that produces a `RichText`, and input queries
/// the host registers kinds for.
library;

export 'src/capabilities/composer_capability_state.dart';
export 'src/capabilities/composer_clock.dart';
export 'src/capabilities/composer_denied_forms.dart';
export 'src/capabilities/composer_op.dart';
export 'src/capabilities/composer_slow_mode_forms.dart';
export 'src/capabilities/composer_slow_mode_state.dart';
export 'src/draft_options/draft_link_page.dart';
export 'src/draft_options/draft_link_page_policy.dart';
export 'src/draft_options/draft_link_part.dart';
export 'src/draft_options/draft_link_rows.dart';
export 'src/draft_options/draft_options_box.dart';
export 'src/draft_options/draft_options_desktop_box.dart';
export 'src/draft_options/draft_options_host.dart';
export 'src/draft_options/draft_options_overlay.dart';
export 'src/draft_options/draft_options_policy.dart';
export 'src/draft_options/draft_options_session.dart';
export 'src/draft_options/overlay_op.dart';
export 'src/input/composer_controller.dart';
export 'src/input/composer_keyboard_intent.dart';
export 'src/input/composer_paste.dart';
export 'src/input/soft_keyboard_mode.dart';
export 'src/link_preview/link_preview_dismissal.dart';
export 'src/menu/composer_formatting_option.dart';
export 'src/menu/composer_menu_hints.dart';
export 'src/menu/composer_menu_policy.dart';
export 'src/menu/composer_pointer_menu_items.dart';
export 'src/menu/composer_spell_checker.dart';
export 'src/query/composer_input_query.dart';
export 'src/query/composer_query_kind.dart';
export 'src/shortcuts/composer_formatting_intents.dart';
export 'src/shortcuts/composer_intents.dart';
export 'src/spec/action_descriptor.dart';
export 'src/spec/composer_header.dart';
export 'src/spec/composer_panel.dart';
export 'src/spec/composer_spec.dart';
export 'src/text/composer_entity_styles.dart';
export 'src/text/composer_text_controller.dart';
export 'src/text/content_span_builder.dart';
export 'src/text/inline_content_span_builder.dart';
export 'src/text/mention_downgrade.dart';
export 'src/view/composer_bottom_fade.dart';
export 'src/view/composer_form_field.dart';
export 'src/view/composer_length_counter.dart';
export 'src/view/composer_metrics.dart';
export 'src/view/composer_primary_style.dart';
export 'src/view/composer_view.dart';
