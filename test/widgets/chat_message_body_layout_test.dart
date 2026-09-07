import 'package:chat_scroll_view/src/chat_widgets/chat_message_body_layout.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('layoutChatMessageBody', () {
    test('header wider than short last line widens body and trails meta', () {
      final layout = layoutChatMessageBody(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: EdgeInsets.zero,
        spacing: 4,
        headerSize: const Size(160, 16),
        contentSize: const Size(20, 20),
        metaSize: const Size(40, 12),
        lastLineWidth: () => 20,
        hasContent: true,
        hasMeta: true,
      );

      expect(layout.size, const Size(160, 36));
      expect(layout.headerOffset, Offset.zero);
      expect(layout.contentOffset, const Offset(0, 16));
      expect(layout.metaOffset, const Offset(120, 24));
    });

    test('wrap decision ignores header width and still trails meta', () {
      // availableWidth = 120; lastLine(50) + spacing(4) + meta(80) = 134 → wrap.
      // Header 100 > content 50 must not keep meta inline.
      final layout = layoutChatMessageBody(
        constraints: const BoxConstraints(maxWidth: 120),
        padding: EdgeInsets.zero,
        spacing: 4,
        headerSize: const Size(100, 16),
        contentSize: const Size(50, 20),
        metaSize: const Size(80, 12),
        lastLineWidth: () => 50,
        hasContent: true,
        hasMeta: true,
      );

      expect(layout.size, const Size(100, 48));
      expect(layout.contentOffset, const Offset(0, 16));
      expect(layout.metaOffset, const Offset(20, 36));
    });
  });
}
