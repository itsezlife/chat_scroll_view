/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'document/svg_document_preview_test.dart' as svg_document_preview_test;
import 'embed/content_embed_resolver_test.dart' as content_embed_resolver_test;
import 'embed/content_embed_test.dart' as content_embed_test;
import 'embed/fake_inline_embed_contract_test.dart'
    as fake_inline_embed_contract_test;
import 'embed/inline_embed_metrics_test.dart' as inline_embed_metrics_test;
import 'glyph/text_glyph_test.dart' as text_glyph_test;
import 'identity/content_media_test.dart' as content_media_test;
import 'preset/asset_presets_test.dart' as asset_presets_test;
import 'scope/content_asset_scope_test.dart' as content_asset_scope_test;
import 'widget/content_asset_view_test.dart' as content_asset_view_test;

void main() {
  group(
    'document/svg_document_preview_test.dart',
    svg_document_preview_test.main,
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
  group('glyph/text_glyph_test.dart', text_glyph_test.main);
  group('identity/content_media_test.dart', content_media_test.main);
  group('preset/asset_presets_test.dart', asset_presets_test.main);
  group('scope/content_asset_scope_test.dart', content_asset_scope_test.main);
  group('widget/content_asset_view_test.dart', content_asset_view_test.main);
}
