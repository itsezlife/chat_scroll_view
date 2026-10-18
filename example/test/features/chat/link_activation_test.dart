import 'package:chat_scroll_view_example/src/features/chat/utils/link_activation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinkActivation.fromUrl', () {
    test('classifies http and https as web', () {
      expect(
        LinkActivation.fromUrl('https://example.com'),
        isA<WebLinkActivation>().having((a) => a.uri.scheme, 'scheme', 'https'),
      );
      expect(
        LinkActivation.fromUrl('http://example.com'),
        isA<WebLinkActivation>(),
      );
    });

    test('classifies the entity schemes of the markdown body', () {
      expect(
        LinkActivation.fromUrl('mention:42'),
        isA<MentionLinkActivation>().having((a) => a.id, 'id', '42'),
      );
      expect(
        LinkActivation.fromUrl('username:alice'),
        isA<UsernameLinkActivation>().having((a) => a.name, 'name', 'alice'),
      );
      expect(
        LinkActivation.fromUrl('hashtag:dart'),
        isA<HashtagLinkActivation>().having((a) => a.tag, 'tag', 'dart'),
      );
    });

    test('an entity scheme with nothing after it is other', () {
      expect(LinkActivation.fromUrl('mention:'), isA<OtherLinkActivation>());
      expect(LinkActivation.fromUrl('username:'), isA<OtherLinkActivation>());
    });

    test('classifies other schemes as other', () {
      expect(
        LinkActivation.fromUrl('mailto:a@b.c'),
        isA<OtherLinkActivation>().having((a) => a.url, 'url', 'mailto:a@b.c'),
      );
    });

    test('a url without a scheme is other', () {
      expect(LinkActivation.fromUrl('a.com'), isA<OtherLinkActivation>());
    });
  });
}
