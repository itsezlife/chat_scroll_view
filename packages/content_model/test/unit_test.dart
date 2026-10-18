/// Every test file of the package, run as one: one compile and one process
/// instead of one per file. `scripts/check` runs this file, and a new
/// `*_test.dart` is imported and grouped here (the workspace lints report
/// one that is not). Each file is a group of its own, so its `setUp` and
/// `tearDown` stay with its tests; the files share the process, so a test
/// that changes global state restores it.
library;

import 'package:test/test.dart';

import 'collection/collection_id_test.dart' as collection_id_test;
import 'collection/collection_test.dart' as collection_test;
import 'data/seams_test.dart' as seams_test;
import 'emoji/emoji_entry_test.dart' as emoji_entry_test;
import 'emoji/emoji_only_text_test.dart' as emoji_only_text_test;
import 'identity/content_descriptor_test.dart' as content_descriptor_test;
import 'identity/content_key_test.dart' as content_key_test;
import 'identity/inline_content_ref_test.dart' as inline_content_ref_test;
import 'markdown/markdown_decode_test.dart' as markdown_decode_test;
import 'markdown/markdown_encode_test.dart' as markdown_encode_test;
import 'markdown/markdown_list_test.dart' as markdown_list_test;
import 'markdown/markdown_round_trip_test.dart' as markdown_round_trip_test;
import 'markdown/markdown_username_hashtag_test.dart'
    as markdown_username_hashtag_test;
import 'rich_text/code_block_test.dart' as code_block_test;
import 'rich_text/list_test.dart' as list_test;
import 'rich_text/rich_text_edit_test.dart' as rich_text_edit_test;
import 'rich_text/rich_text_json_test.dart' as rich_text_json_test;
import 'rich_text/rich_text_test.dart' as rich_text_test;
import 'rich_text/username_hashtag_test.dart' as username_hashtag_test;
import 'store/deferred_recents_store_test.dart' as deferred_recents_store_test;
import 'store/key_value_preference_store_test.dart'
    as key_value_preference_store_test;
import 'store/key_value_recents_store_test.dart'
    as key_value_recents_store_test;
import 'store/loaded_stores_only_test.dart' as loaded_stores_only_test;
import 'testing/fake_collection_source_test.dart'
    as fake_collection_source_test;
import 'testing/fake_content_resolver_test.dart' as fake_content_resolver_test;
import 'testing/fake_glyph_support_test.dart' as fake_glyph_support_test;
import 'testing/fake_key_value_store_test.dart' as fake_key_value_store_test;
import 'testing/fake_keyword_source_test.dart' as fake_keyword_source_test;
import 'testing/fake_preference_store_test.dart' as fake_preference_store_test;
import 'testing/fake_recents_store_test.dart' as fake_recents_store_test;
import 'testing/fake_rich_clipboard_test.dart' as fake_rich_clipboard_test;
import 'testing/fake_search_source_test.dart' as fake_search_source_test;

void main() {
  group('collection/collection_id_test.dart', collection_id_test.main);
  group('collection/collection_test.dart', collection_test.main);
  group('data/seams_test.dart', seams_test.main);
  group('emoji/emoji_entry_test.dart', emoji_entry_test.main);
  group('emoji/emoji_only_text_test.dart', emoji_only_text_test.main);
  group('identity/content_descriptor_test.dart', content_descriptor_test.main);
  group('identity/content_key_test.dart', content_key_test.main);
  group('identity/inline_content_ref_test.dart', inline_content_ref_test.main);
  group('markdown/markdown_decode_test.dart', markdown_decode_test.main);
  group('markdown/markdown_encode_test.dart', markdown_encode_test.main);
  group('markdown/markdown_list_test.dart', markdown_list_test.main);
  group(
    'markdown/markdown_round_trip_test.dart',
    markdown_round_trip_test.main,
  );
  group(
    'markdown/markdown_username_hashtag_test.dart',
    markdown_username_hashtag_test.main,
  );
  group('rich_text/code_block_test.dart', code_block_test.main);
  group('rich_text/list_test.dart', list_test.main);
  group('rich_text/rich_text_edit_test.dart', rich_text_edit_test.main);
  group('rich_text/rich_text_json_test.dart', rich_text_json_test.main);
  group('rich_text/rich_text_test.dart', rich_text_test.main);
  group('rich_text/username_hashtag_test.dart', username_hashtag_test.main);
  group(
    'store/deferred_recents_store_test.dart',
    deferred_recents_store_test.main,
  );
  group(
    'store/key_value_preference_store_test.dart',
    key_value_preference_store_test.main,
  );
  group(
    'store/key_value_recents_store_test.dart',
    key_value_recents_store_test.main,
  );
  group('store/loaded_stores_only_test.dart', loaded_stores_only_test.main);
  group(
    'testing/fake_collection_source_test.dart',
    fake_collection_source_test.main,
  );
  group(
    'testing/fake_content_resolver_test.dart',
    fake_content_resolver_test.main,
  );
  group('testing/fake_glyph_support_test.dart', fake_glyph_support_test.main);
  group(
    'testing/fake_key_value_store_test.dart',
    fake_key_value_store_test.main,
  );
  group('testing/fake_keyword_source_test.dart', fake_keyword_source_test.main);
  group(
    'testing/fake_preference_store_test.dart',
    fake_preference_store_test.main,
  );
  group('testing/fake_recents_store_test.dart', fake_recents_store_test.main);
  group('testing/fake_rich_clipboard_test.dart', fake_rich_clipboard_test.main);
  group('testing/fake_search_source_test.dart', fake_search_source_test.main);
}
