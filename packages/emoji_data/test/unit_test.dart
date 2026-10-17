/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:test/test.dart';

import 'audit/shipped_catalog_test.dart' as shipped_catalog_test;
import 'catalog/emoji_catalog_test.dart' as emoji_catalog_test;
import 'collections/emoji_collection_source_test.dart'
    as emoji_collection_source_test;
import 'collections/spoken_names_test.dart' as spoken_names_test;
import 'glyph_probe/glyph_art_fingerprint_test.dart'
    as glyph_art_fingerprint_test;
import 'glyph_probe/glyph_pixel_hash_test.dart' as glyph_pixel_hash_test;
import 'glyph_probe/missing_glyph_probe_contract_test.dart'
    as missing_glyph_probe_contract_test;
import 'glyph_probe/missing_glyph_probe_test.dart' as missing_glyph_probe_test;
import 'glyph_probe/paced_glyph_probe_pass_test.dart'
    as paced_glyph_probe_pass_test;
import 'keywords/bundled_keyword_source_test.dart'
    as bundled_keyword_source_test;
import 'keywords/layered_keyword_source_test.dart'
    as layered_keyword_source_test;
import 'loading/emoji_catalog_loader_test.dart' as emoji_catalog_loader_test;
import 'search/emoji_search_source_test.dart' as emoji_search_source_test;
import 'search/keyword_index_test.dart' as keyword_index_test;

void main() {
  group('audit/shipped_catalog_test.dart', shipped_catalog_test.main);
  group('catalog/emoji_catalog_test.dart', emoji_catalog_test.main);
  group(
    'collections/emoji_collection_source_test.dart',
    emoji_collection_source_test.main,
  );
  group('collections/spoken_names_test.dart', spoken_names_test.main);
  group(
    'glyph_probe/glyph_art_fingerprint_test.dart',
    glyph_art_fingerprint_test.main,
  );
  group('glyph_probe/glyph_pixel_hash_test.dart', glyph_pixel_hash_test.main);
  group(
    'glyph_probe/missing_glyph_probe_contract_test.dart',
    missing_glyph_probe_contract_test.main,
  );
  group(
    'glyph_probe/missing_glyph_probe_test.dart',
    missing_glyph_probe_test.main,
  );
  group(
    'glyph_probe/paced_glyph_probe_pass_test.dart',
    paced_glyph_probe_pass_test.main,
  );
  group(
    'keywords/bundled_keyword_source_test.dart',
    bundled_keyword_source_test.main,
  );
  group(
    'keywords/layered_keyword_source_test.dart',
    layered_keyword_source_test.main,
  );
  group(
    'loading/emoji_catalog_loader_test.dart',
    emoji_catalog_loader_test.main,
  );
  group('search/emoji_search_source_test.dart', emoji_search_source_test.main);
  group('search/keyword_index_test.dart', keyword_index_test.main);
}
