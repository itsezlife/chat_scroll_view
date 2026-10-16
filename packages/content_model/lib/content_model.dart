/// Pure-Dart content identity and collection value types and the data seams
/// the catalogue packages share. The seams signal change through
/// `package:listen`, which this library does not re-export.
library;

export 'src/collection/collection.dart';
export 'src/collection/collection_contents.dart';
export 'src/collection/collection_id.dart';
export 'src/data/collection_source.dart';
export 'src/data/content_resolver.dart';
export 'src/data/glyph_support.dart';
export 'src/data/key_value_store.dart';
export 'src/data/keyword_source.dart';
export 'src/data/preference_store.dart';
export 'src/data/recents_store.dart';
export 'src/data/search_source.dart';
export 'src/emoji/emoji_entry.dart';
export 'src/identity/content_descriptor.dart';
export 'src/identity/content_key.dart';
export 'src/identity/inline_content_ref.dart';
export 'src/rich_text/entity.dart';
export 'src/rich_text/entity_kind.dart';
export 'src/rich_text/rich_text.dart';
export 'src/store/key_value_preference_store.dart';
export 'src/store/key_value_recents_store.dart';
