/// A slot-based chat composer: a host-built `ComposerSpec` describes the
/// header, panel and actions; `ComposerView` lays them out in a glass island
/// and publishes its extent. Beside it sit the input-only controller, the
/// entity-aware text controller that produces a `RichText`, and input queries
/// the host registers kinds for.
library;

export 'src/input/composer_controller.dart';
export 'src/input/soft_keyboard_mode.dart';
export 'src/query/composer_input_query.dart';
export 'src/query/composer_query_kind.dart';
export 'src/shortcuts/composer_intents.dart';
export 'src/spec/action_descriptor.dart';
export 'src/spec/composer_header.dart';
export 'src/spec/composer_panel.dart';
export 'src/spec/composer_spec.dart';
export 'src/text/composer_entity_styles.dart';
export 'src/text/composer_text_controller.dart';
export 'src/text/inline_content_span_builder.dart';
export 'src/view/composer_bottom_fade.dart';
export 'src/view/composer_metrics.dart';
export 'src/view/composer_view.dart';
