/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'atlas/bake_governor_test.dart' as bake_governor_test;
import 'atlas/cache/computed_glyph_art_version_test.dart'
    as computed_glyph_art_version_test;
import 'atlas/cache/file_glyph_stores_test.dart' as file_glyph_stores_test;
import 'atlas/cache/glyph_art_fingerprint_cache_test.dart'
    as glyph_art_fingerprint_cache_test;
import 'atlas/cache/glyph_atlas_persistence_test.dart'
    as glyph_atlas_persistence_test;
import 'atlas/cache/glyph_cache_key_test.dart' as glyph_cache_key_test;
import 'atlas/cache/glyph_cache_store_platform_test.dart'
    as glyph_cache_store_platform_test;
import 'atlas/callback_glyph_bake_observer_test.dart'
    as callback_glyph_bake_observer_test;
import 'atlas/current_catalogue_test.dart' as current_catalogue_test;
import 'atlas/glyph_atlas_contracts_test.dart' as glyph_atlas_contracts_test;
import 'atlas/glyph_atlas_index_test.dart' as glyph_atlas_index_test;
import 'atlas/glyph_atlas_platform_test.dart' as glyph_atlas_platform_test;
import 'atlas/glyph_atlas_residency_test.dart' as glyph_atlas_residency_test;
import 'atlas/glyph_atlas_test.dart' as glyph_atlas_test;
import 'atlas/glyph_bake_scheduler_test.dart' as glyph_bake_scheduler_test;
import 'atlas/glyph_baker_observer_test.dart' as glyph_baker_observer_test;
import 'atlas/glyph_baker_priority_test.dart' as glyph_baker_priority_test;
import 'atlas/glyph_baker_test.dart' as glyph_baker_test;
import 'atlas/glyph_page_residency_test.dart' as glyph_page_residency_test;
import 'atlas/glyph_pixel_reader_test.dart' as glyph_pixel_reader_test;
import 'atlas/paragraph_glyph_rasteriser_test.dart'
    as paragraph_glyph_rasteriser_test;
import 'atlas/system_memory_pressure_test.dart' as system_memory_pressure_test;
import 'source/glyph_sprite_source_contract_test.dart'
    as glyph_sprite_source_contract_test;
import 'source/layered_glyph_source_test.dart' as layered_glyph_source_test;

void main() {
  group('atlas/bake_governor_test.dart', bake_governor_test.main);
  group(
    'atlas/cache/computed_glyph_art_version_test.dart',
    computed_glyph_art_version_test.main,
  );
  group('atlas/cache/file_glyph_stores_test.dart', file_glyph_stores_test.main);
  group(
    'atlas/cache/glyph_art_fingerprint_cache_test.dart',
    glyph_art_fingerprint_cache_test.main,
  );
  group(
    'atlas/cache/glyph_atlas_persistence_test.dart',
    glyph_atlas_persistence_test.main,
  );
  group('atlas/cache/glyph_cache_key_test.dart', glyph_cache_key_test.main);
  group(
    'atlas/cache/glyph_cache_store_platform_test.dart',
    glyph_cache_store_platform_test.main,
  );
  group(
    'atlas/callback_glyph_bake_observer_test.dart',
    callback_glyph_bake_observer_test.main,
  );
  group('atlas/current_catalogue_test.dart', current_catalogue_test.main);
  group(
    'atlas/glyph_atlas_contracts_test.dart',
    glyph_atlas_contracts_test.main,
  );
  group('atlas/glyph_atlas_index_test.dart', glyph_atlas_index_test.main);
  group('atlas/glyph_atlas_platform_test.dart', glyph_atlas_platform_test.main);
  group(
    'atlas/glyph_atlas_residency_test.dart',
    glyph_atlas_residency_test.main,
  );
  group('atlas/glyph_atlas_test.dart', glyph_atlas_test.main);
  group('atlas/glyph_bake_scheduler_test.dart', glyph_bake_scheduler_test.main);
  group('atlas/glyph_baker_observer_test.dart', glyph_baker_observer_test.main);
  group('atlas/glyph_baker_priority_test.dart', glyph_baker_priority_test.main);
  group('atlas/glyph_baker_test.dart', glyph_baker_test.main);
  group('atlas/glyph_page_residency_test.dart', glyph_page_residency_test.main);
  group('atlas/glyph_pixel_reader_test.dart', glyph_pixel_reader_test.main);
  group(
    'atlas/paragraph_glyph_rasteriser_test.dart',
    paragraph_glyph_rasteriser_test.main,
  );
  group(
    'atlas/system_memory_pressure_test.dart',
    system_memory_pressure_test.main,
  );
  group(
    'source/glyph_sprite_source_contract_test.dart',
    glyph_sprite_source_contract_test.main,
  );
  group(
    'source/layered_glyph_source_test.dart',
    layered_glyph_source_test.main,
  );
}
