/// The input side of a chat composer: an input-only controller, an
/// entity-aware text controller that produces a `RichText`, and input queries
/// the host registers kinds for.
library;

export 'src/input/composer_controller.dart';
export 'src/input/soft_keyboard_mode.dart';
export 'src/query/composer_input_query.dart';
export 'src/query/composer_query_kind.dart';
export 'src/text/composer_entity_styles.dart';
export 'src/text/composer_text_controller.dart';
export 'src/text/inline_content_span_builder.dart';
