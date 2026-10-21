/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'asset/asset_cache_budget_test.dart' as asset_cache_budget_test;
import 'asset/asset_cache_demand_test.dart' as asset_cache_demand_test;
import 'asset/asset_cache_failure_test.dart' as asset_cache_failure_test;
import 'asset/asset_cache_playback_test.dart' as asset_cache_playback_test;
import 'asset/asset_cache_scope_test.dart' as asset_cache_scope_test;
import 'asset/asset_playback_test.dart' as asset_playback_test;
import 'asset/asset_spec_test.dart' as asset_spec_test;
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
import 'benchmark/asset_cache_churn_bench_test.dart'
    as asset_cache_churn_bench_test;
import 'benchmark/asset_cache_ratio_bench_test.dart'
    as asset_cache_ratio_bench_test;
import 'embed/content_embed_resolver_test.dart' as content_embed_resolver_test;
import 'embed/content_embed_test.dart' as content_embed_test;
import 'embed/fake_inline_embed_contract_test.dart'
    as fake_inline_embed_contract_test;
import 'embed/inline_embed_metrics_test.dart' as inline_embed_metrics_test;
import 'glyph/glyph_binding_test.dart' as glyph_binding_test;
import 'glyph/glyph_sprite_source_contract_test.dart'
    as glyph_sprite_source_contract_test;
import 'glyph/layered_glyph_source_test.dart' as layered_glyph_source_test;
import 'glyph/text_glyph_producer_test.dart' as text_glyph_producer_test;
import 'pipeline/cancellation_token_test.dart' as cancellation_token_test;
import 'pipeline/decoder_registry_test.dart' as decoder_registry_test;
import 'pipeline/fake_adapters_contract_test.dart'
    as fake_adapters_contract_test;
import 'pipeline/pipeline_flow_test.dart' as pipeline_flow_test;
import 'pipeline/pipeline_offline_test.dart' as pipeline_offline_test;
import 'pipeline/pipeline_orchestration_test.dart'
    as pipeline_orchestration_test;
import 'pipeline/pipeline_resolver_test.dart' as pipeline_resolver_test;
import 'playback/playback_activity_test.dart' as playback_activity_test;
import 'playback/playback_clock_test.dart' as playback_clock_test;
import 'playback/playback_lifecycle_source_contract_test.dart'
    as playback_lifecycle_source_contract_test;
import 'playback/playback_tick_source_contract_test.dart'
    as playback_tick_source_contract_test;
import 'preset/asset_presets_test.dart' as asset_presets_test;
import 'widget/asset_cache_provider_test.dart' as asset_cache_provider_test;
import 'widget/content_view_test.dart' as content_view_test;

void main() {
  group('asset/asset_cache_budget_test.dart', asset_cache_budget_test.main);
  group('asset/asset_cache_demand_test.dart', asset_cache_demand_test.main);
  group('asset/asset_cache_failure_test.dart', asset_cache_failure_test.main);
  group('asset/asset_cache_playback_test.dart', asset_cache_playback_test.main);
  group('asset/asset_cache_scope_test.dart', asset_cache_scope_test.main);
  group('asset/asset_playback_test.dart', asset_playback_test.main);
  group('asset/asset_spec_test.dart', asset_spec_test.main);
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
    'benchmark/asset_cache_churn_bench_test.dart',
    asset_cache_churn_bench_test.main,
  );
  group(
    'benchmark/asset_cache_ratio_bench_test.dart',
    asset_cache_ratio_bench_test.main,
  );
  group(
    'embed/content_embed_resolver_test.dart',
    content_embed_resolver_test.main,
  );
  group('embed/content_embed_test.dart', content_embed_test.main);
  group(
    'embed/fake_inline_embed_contract_test.dart',
    fake_inline_embed_contract_test.main,
  );
  group('embed/inline_embed_metrics_test.dart', inline_embed_metrics_test.main);
  group('glyph/glyph_binding_test.dart', glyph_binding_test.main);
  group(
    'glyph/glyph_sprite_source_contract_test.dart',
    glyph_sprite_source_contract_test.main,
  );
  group('glyph/layered_glyph_source_test.dart', layered_glyph_source_test.main);
  group('glyph/text_glyph_producer_test.dart', text_glyph_producer_test.main);
  group('pipeline/cancellation_token_test.dart', cancellation_token_test.main);
  group('pipeline/decoder_registry_test.dart', decoder_registry_test.main);
  group(
    'pipeline/fake_adapters_contract_test.dart',
    fake_adapters_contract_test.main,
  );
  group('pipeline/pipeline_flow_test.dart', pipeline_flow_test.main);
  group('pipeline/pipeline_offline_test.dart', pipeline_offline_test.main);
  group(
    'pipeline/pipeline_orchestration_test.dart',
    pipeline_orchestration_test.main,
  );
  group('pipeline/pipeline_resolver_test.dart', pipeline_resolver_test.main);
  group('playback/playback_activity_test.dart', playback_activity_test.main);
  group('playback/playback_clock_test.dart', playback_clock_test.main);
  group(
    'playback/playback_lifecycle_source_contract_test.dart',
    playback_lifecycle_source_contract_test.main,
  );
  group(
    'playback/playback_tick_source_contract_test.dart',
    playback_tick_source_contract_test.main,
  );
  group('preset/asset_presets_test.dart', asset_presets_test.main);
  group(
    'widget/asset_cache_provider_test.dart',
    asset_cache_provider_test.main,
  );
  group('widget/content_view_test.dart', content_view_test.main);
}
