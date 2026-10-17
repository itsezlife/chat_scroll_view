/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:test/test.dart';

import 'assets/shipped_assets_test.dart' as shipped_assets_test;
import 'emoji_catalog_pack_assets_test.dart' as emoji_catalog_pack_assets_test;
import 'generator/asset_generator_test.dart' as asset_generator_test;
import 'generator/cldr_annotations_test.dart' as cldr_annotations_test;
import 'generator/emoji_keyword_pack_builder_test.dart'
    as emoji_keyword_pack_builder_test;
import 'generator/emoji_test_file_test.dart' as emoji_test_file_test;
import 'generator/inputs_lock_test.dart' as inputs_lock_test;
import 'generator/structure_builder_test.dart' as structure_builder_test;
import 'keywords/emoji_keyword_pack_test.dart' as emoji_keyword_pack_test;
import 'structure/emoji_catalog_structure_test.dart'
    as emoji_catalog_structure_test;

void main() {
  group('assets/shipped_assets_test.dart', shipped_assets_test.main);
  group(
    'emoji_catalog_pack_assets_test.dart',
    emoji_catalog_pack_assets_test.main,
  );
  group('generator/asset_generator_test.dart', asset_generator_test.main);
  group('generator/cldr_annotations_test.dart', cldr_annotations_test.main);
  group(
    'generator/emoji_keyword_pack_builder_test.dart',
    emoji_keyword_pack_builder_test.main,
  );
  group('generator/emoji_test_file_test.dart', emoji_test_file_test.main);
  group('generator/inputs_lock_test.dart', inputs_lock_test.main);
  group('generator/structure_builder_test.dart', structure_builder_test.main);
  group('keywords/emoji_keyword_pack_test.dart', emoji_keyword_pack_test.main);
  group(
    'structure/emoji_catalog_structure_test.dart',
    emoji_catalog_structure_test.main,
  );
}
