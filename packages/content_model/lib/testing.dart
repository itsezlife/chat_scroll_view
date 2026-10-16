/// Fakes and contract suites for the seams of `content_model`.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them. Hosts and adapter packages run the `run...Contract`
/// suites against their own implementations and use the fakes in their tests.
library;

export 'src/testing/collection_source_contract.dart';
export 'src/testing/content_resolver_contract.dart';
export 'src/testing/fake_collection_source.dart';
export 'src/testing/fake_content_resolver.dart';
export 'src/testing/fake_glyph_support.dart';
export 'src/testing/fake_key_value_store.dart';
export 'src/testing/fake_keyword_source.dart';
export 'src/testing/fake_pages.dart';
export 'src/testing/fake_preference_store.dart';
export 'src/testing/fake_recents_store.dart';
export 'src/testing/fake_search_source.dart';
export 'src/testing/glyph_support_contract.dart';
export 'src/testing/key_value_store_contract.dart';
export 'src/testing/keyword_source_contract.dart';
export 'src/testing/preference_store_contract.dart';
export 'src/testing/recents_store_contract.dart';
export 'src/testing/search_source_contract.dart';
