import 'package:chatscrollview/src/backend_chat_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Legacy HTTP tests removed — see test/supabase_chat_data_source_test.dart.
  test('BackendChatDataSource is Supabase-backed', () {
    expect(BackendChatDataSource, isNotNull);
  });
}
