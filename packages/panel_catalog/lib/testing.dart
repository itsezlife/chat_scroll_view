/// Fakes for the seams of `panel_catalog`.
///
/// Opt-in: production entry points never export these, and production code
/// never imports them.
library;

export 'src/testing/catalog_scroll_position_contract.dart';
export 'src/testing/fake_catalog_scroll_position.dart';
export 'src/testing/fake_catalog_snapshot_source.dart';
