/// What the example's local sources do with a message body: detect once as a
/// message is materialised, and store a sent or edited body as the composer
/// made it.
library;

import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeneratedChatDataSource bodies', () {
    test('sendMessage stores the body it was given', () {
      final ds = GeneratedChatDataSource(messageCount: 0);
      addTearDown(ds.dispose);
      const sent = 'see [https://example.com](https://example.com) and @alice';

      final message = ds.sendMessage(sender: 'Hixie', content: sent);

      expect(message.content, sent);
    });

    test('editMessage stores the body it was given', () {
      final ds = GeneratedChatDataSource(messageCount: 0);
      addTearDown(ds.dispose);
      final sent = ds.sendMessage(sender: 'Hixie', content: 'plain');
      const edited = 'hi [@carol](username:carol)';

      ds.editMessage(sent, edited);

      expect(ds.getMessage(sent.id)?.text, edited);
    });
  });
}
