import 'dart:convert';
import 'dart:typed_data';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

void main() {
  final url = Uri.parse('https://example.com/post/1?ref=chat');

  final description = RichText('Read the bold part, then the link.', const [
    Entity(9, 4, EntityKind.bold),
    Entity(29, 4, EntityKind.link('https://example.com/more')),
  ]);

  final photo = ContentDescriptor(
    key: const ContentKey.external('photo-1'),
    semanticKind: SemanticKind.unknown,
    mediaForm: MediaForm.still,
    size: const ContentSize(1280, 720),
    byteSize: 204800,
    thumbnail: const ThumbnailRef('thumb-1'),
    preview: ContentPreview.raster(Uint8List.fromList([1, 2, 3, 250])),
  );

  const media = ContentDescriptor(
    key: ContentKey.document('video-1'),
    semanticKind: SemanticKind.gif,
    mediaForm: MediaForm.video,
    animated: true,
    tintable: true,
    locked: true,
    size: ContentSize(640, 360),
    byteSize: 1048576,
    duration: Duration(milliseconds: 12500),
    streamable: true,
    preview: ContentPreview.outline('M0 0h10v10z', ContentSize(512, 512)),
    spokenName: 'clip',
    shortcode: ':clip:',
    pack: PackId('pack-1'),
    fileName: 'clip.mp4',
    mimeType: 'video/mp4',
  );

  final page = LinkPreview(
    url: url,
    displayUrl: 'example.com/post/1',
    type: 'video',
    siteName: 'Example',
    title: 'A post',
    author: 'Ann',
    description: description,
    photo: photo,
    media: media,
    duration: const Duration(seconds: 12),
    hasLargeMedia: false,
  );

  /// Writes, then reads back through a JSON string, as a host's wire does.
  Map<String, Object?> throughJson(Map<String, Object?> message) =>
      (jsonDecode(jsonEncode(message)) as Map).cast<String, Object?>();

  group('round trip', () {
    test('every option, with the page', () {
      final sent = MessageLinkPreview(
        options: LinkPreviewOptions(
          url: url,
          media: LinkPreviewMedia.large,
          removed: true,
        ),
        page: page,
      );
      final message = <String, Object?>{'body': 'hello'};

      LinkPreviewWire.write(message, linkPreview: sent, invertMedia: true);
      final read = throughJson(message);

      expect(LinkPreviewWire.readLinkPreview(read), sent);
      expect(LinkPreviewWire.readInvertMedia(read), isTrue);
      expect(read['body'], 'hello');
    });

    test('options without a page', () {
      final sent = MessageLinkPreview(
        options: LinkPreviewOptions(url: url, media: LinkPreviewMedia.small),
      );
      final message = <String, Object?>{};

      LinkPreviewWire.write(message, linkPreview: sent);
      final read = throughJson(message);

      expect(LinkPreviewWire.readLinkPreview(read), sent);
      expect(LinkPreviewWire.readLinkPreview(read)!.page, isNull);
      expect((read['linkPreview']! as Map).containsKey('page'), isFalse);
    });

    test('a page of its url alone', () {
      final sent = MessageLinkPreview(
        options: LinkPreviewOptions(url: url),
        page: LinkPreview(url: url),
      );
      final message = <String, Object?>{};

      LinkPreviewWire.write(message, linkPreview: sent);

      expect(LinkPreviewWire.readLinkPreview(throughJson(message)), sent);
      expect((message['linkPreview']! as Map)['page'], {'url': url.toString()});
    });

    test('a descriptor of its key alone', () {
      final sent = MessageLinkPreview(
        options: LinkPreviewOptions(url: url),
        page: LinkPreview(
          url: url,
          photo: const ContentDescriptor(key: ContentKey.unicode('👍')),
        ),
      );
      final message = <String, Object?>{};

      LinkPreviewWire.write(message, linkPreview: sent);

      expect(LinkPreviewWire.readLinkPreview(throughJson(message)), sent);
    });

    test('the description keeps its entities', () {
      final message = <String, Object?>{};

      LinkPreviewWire.write(
        message,
        linkPreview: MessageLinkPreview(
          options: LinkPreviewOptions(url: url),
          page: page,
        ),
      );
      final read = LinkPreviewWire.readLinkPreview(throughJson(message))!;

      expect(read.page!.description, description);
      expect(read.page!.description.entities, hasLength(2));
    });
  });

  group('write', () {
    test('writes the wire shape the contract names', () {
      final message = <String, Object?>{};

      LinkPreviewWire.write(
        message,
        linkPreview: MessageLinkPreview(options: LinkPreviewOptions(url: url)),
      );

      expect(message, {
        'linkPreview': {
          'url': 'https://example.com/post/1?ref=chat',
          'media': 'auto',
          'removed': false,
        },
      });
    });

    test('does not write invertMedia when it is false', () {
      final message = <String, Object?>{};

      LinkPreviewWire.write(message);

      expect(message.containsKey('invertMedia'), isFalse);
      expect(message.containsKey('linkPreview'), isFalse);
    });

    test('clears fields a previous write left', () {
      final message = <String, Object?>{'body': 'x'};
      LinkPreviewWire.write(
        message,
        linkPreview: MessageLinkPreview(options: LinkPreviewOptions(url: url)),
        invertMedia: true,
      );

      LinkPreviewWire.write(message);

      expect(message, {'body': 'x'});
    });

    test('writes only JSON values', () {
      final message = <String, Object?>{};

      LinkPreviewWire.write(
        message,
        linkPreview: MessageLinkPreview(
          options: LinkPreviewOptions(url: url),
          page: page,
        ),
        invertMedia: true,
      );

      expect(throughJson(message), message);
    });
  });

  group('read', () {
    test('a message without linkPreview has no preview', () {
      final recorder = RecordingDiagnostics.install();

      expect(LinkPreviewWire.readLinkPreview({'body': 'hi'}), isNull);
      expect(LinkPreviewWire.readInvertMedia({'body': 'hi'}), isFalse);
      expect(recorder.events, isEmpty);
    });

    test('an unknown media value reads as auto', () {
      final recorder = RecordingDiagnostics.install();

      final read = LinkPreviewWire.readLinkPreview({
        'linkPreview': {'url': 'https://example.com', 'media': 'huge'},
      }, scrollId: 'm1');

      expect(read!.options.media, LinkPreviewMedia.auto);
      expect(recorder.events, [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.linkPreview,
          op: LinkPreviewOp.codecTolerated,
          correlation: const ChatCorrelation(scrollId: 'm1'),
          fields: {'field': 'linkPreview.media', 'kind': 'unknownValue'},
        ),
      ]);
    });

    test('a missing media or removed reads as the default', () {
      final read = LinkPreviewWire.readLinkPreview({
        'linkPreview': {'url': 'https://example.com'},
      });

      expect(
        read,
        MessageLinkPreview(
          options: LinkPreviewOptions(url: Uri.parse('https://example.com')),
        ),
      );
    });

    test('a linkPreview without a usable url is no preview', () {
      final recorder = RecordingDiagnostics.install();

      expect(
        LinkPreviewWire.readLinkPreview({
          'linkPreview': {'media': 'small'},
        }, scrollId: 'm1'),
        isNull,
      );
      expect(
        LinkPreviewWire.readLinkPreview({
          'linkPreview': {'url': 42},
        }, scrollId: 'm2'),
        isNull,
      );
      expect(LinkPreviewWire.readLinkPreview({'linkPreview': 'nope'}), isNull);
      expect(recorder.events, [
        isChatEvent(
          op: LinkPreviewOp.codecTolerated,
          correlation: const ChatCorrelation(scrollId: 'm1'),
          fields: {'field': 'linkPreview.url', 'kind': 'missing'},
        ),
        isChatEvent(
          op: LinkPreviewOp.codecTolerated,
          correlation: const ChatCorrelation(scrollId: 'm2'),
          fields: {'field': 'linkPreview.url', 'kind': 'wrongType'},
        ),
        isChatEvent(
          op: LinkPreviewOp.codecTolerated,
          fields: {'field': 'linkPreview', 'kind': 'wrongType'},
        ),
      ]);
    });

    test('a damaged page is dropped and the options kept', () {
      final recorder = RecordingDiagnostics.install();

      final read = LinkPreviewWire.readLinkPreview({
        'linkPreview': {
          'url': 'https://example.com',
          'media': 'large',
          'removed': false,
          'page': {'title': 'no url'},
        },
      });

      expect(
        read,
        MessageLinkPreview(
          options: LinkPreviewOptions(
            url: Uri.parse('https://example.com'),
            media: LinkPreviewMedia.large,
          ),
        ),
      );
      expect(recorder.events, [
        isChatEvent(
          op: LinkPreviewOp.codecTolerated,
          fields: {'field': 'page.url', 'kind': 'missing'},
        ),
      ]);
    });

    test('a page field of the wrong type is left out', () {
      final recorder = RecordingDiagnostics.install();

      final read = LinkPreviewWire.readLinkPreview({
        'linkPreview': {
          'url': 'https://example.com',
          'page': {
            'url': 'https://example.com',
            'title': 7,
            'photo': {'key': 'not a key'},
            'durationMs': 'long',
          },
        },
      });

      expect(read!.page, LinkPreview(url: Uri.parse('https://example.com')));
      expect(
        recorder.events.map((event) => event.fields),
        unorderedEquals([
          {'field': 'page.title', 'kind': 'wrongType'},
          {'field': 'page.photo.key', 'kind': 'unparseable'},
          {'field': 'page.durationMs', 'kind': 'wrongType'},
        ]),
      );
    });

    test('a damaged descriptor fact is left out and the descriptor kept', () {
      final recorder = RecordingDiagnostics.install();

      LinkPreview pageWith(Map<String, Object?> photo) =>
          LinkPreviewWire.readLinkPreview({
            'linkPreview': {
              'url': 'https://example.com',
              'page': {'url': 'https://example.com', 'photo': photo},
            },
          })!.page!;

      const bare = ContentDescriptor(key: ContentKey.document('1'));
      expect(
        pageWith({'key': 'document:1', 'width': -4, 'height': 3}).photo,
        bare,
      );
      expect(pageWith({'key': 'document:1', 'byteSize': -1}).photo, bare);
      expect(
        pageWith({
          'key': 'document:1',
          'preview': {'raster': '%%%'},
        }).photo,
        bare,
      );
      expect(
        pageWith({
          'key': 'document:1',
          'preview': {'outline': 'M0 0z'},
        }).photo,
        bare,
      );
      expect(pageWith({'width': 4}).photo, isNull);
      expect(recorder.events.map((event) => event.fields), [
        {'field': 'page.photo.size', 'kind': 'unparseable'},
        {'field': 'page.photo.byteSize', 'kind': 'unparseable'},
        {'field': 'page.photo.preview.raster', 'kind': 'unparseable'},
        {'field': 'page.photo.preview.size', 'kind': 'missing'},
        {'field': 'page.photo.key', 'kind': 'missing'},
      ]);
    });

    test('an unknown descriptor kind or form reads as unknown', () {
      final read = LinkPreviewWire.readLinkPreview({
        'linkPreview': {
          'url': 'https://example.com',
          'page': {
            'url': 'https://example.com',
            'media': {
              'key': 'document:9',
              'semanticKind': 'hologram',
              'mediaForm': 'smell',
            },
          },
        },
      });

      expect(
        read!.page!.media,
        const ContentDescriptor(key: ContentKey.document('9')),
      );
    });

    test('an invertMedia that is not a bool reads as false', () {
      final recorder = RecordingDiagnostics.install();

      expect(
        LinkPreviewWire.readInvertMedia({'invertMedia': 'yes'}, scrollId: 'm'),
        isFalse,
      );
      expect(recorder.events, [
        isChatEvent(
          op: LinkPreviewOp.codecTolerated,
          correlation: const ChatCorrelation(scrollId: 'm'),
          fields: {'field': 'invertMedia', 'kind': 'wrongType'},
        ),
      ]);
    });

    test('no event carries the content it read', () {
      final recorder = RecordingDiagnostics.install();

      LinkPreviewWire.readLinkPreview({
        'linkPreview': {
          'url': 'https://example.com/secret/path',
          'media': 'secret-media',
          'page': {
            'url': 'https://example.com/secret/path',
            'title': ['secret title'],
          },
        },
      });

      expect(recorder.events, hasLength(2));
      for (final event in recorder.events) {
        expect(event.fields.values.join(' '), isNot(contains('secret')));
      }
    });
  });
}
