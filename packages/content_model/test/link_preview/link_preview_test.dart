import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  final url = Uri.parse('https://example.com/post/1');

  group('LinkPreview', () {
    const photo = ContentDescriptor(key: ContentKey.document('p1'));
    const media = ContentDescriptor(key: ContentKey.document('m1'));

    LinkPreview full({
      Uri? url,
      String displayUrl = 'example.com/post/1',
      String type = 'article',
      String siteName = 'Example',
      String title = 'A post',
      String author = 'Ann',
      RichText? description,
      ContentDescriptor photo = photo,
      ContentDescriptor media = media,
      Duration duration = const Duration(seconds: 12),
      bool hasLargeMedia = true,
    }) => LinkPreview(
      url: url ?? Uri.parse('https://example.com/post/1'),
      displayUrl: displayUrl,
      type: type,
      siteName: siteName,
      title: title,
      author: author,
      description:
          description ??
          RichText('Bold words', const [Entity(0, 4, EntityKind.bold)]),
      photo: photo,
      media: media,
      duration: duration,
      hasLargeMedia: hasLargeMedia,
    );

    test('is equal to a page of the same fields', () {
      expect(full(), full());
      expect(full().hashCode, full().hashCode);
    });

    test('differs when any field differs', () {
      final base = full();
      final others = [
        full(url: Uri.parse('https://example.com/other')),
        full(displayUrl: 'other'),
        full(type: 'photo'),
        full(siteName: 'Other'),
        full(title: 'Other'),
        full(author: 'Other'),
        full(description: const RichText.plain('Bold words')),
        full(photo: const ContentDescriptor(key: ContentKey.document('p2'))),
        full(media: const ContentDescriptor(key: ContentKey.document('m2'))),
        full(duration: const Duration(seconds: 13)),
        full(hasLargeMedia: false),
      ];
      for (final other in others) {
        expect(other, isNot(base));
      }
    });

    test('knows nothing beyond its url by default', () {
      final page = LinkPreview(url: url);

      expect(page.displayUrl, isNull);
      expect(page.type, isNull);
      expect(page.siteName, isNull);
      expect(page.title, isNull);
      expect(page.author, isNull);
      expect(page.description, RichText.empty);
      expect(page.photo, isNull);
      expect(page.media, isNull);
      expect(page.duration, isNull);
      expect(page.hasLargeMedia, isNull);
    });
  });

  group('LinkPreviewOptions', () {
    test('defaults to the automatic size, not removed', () {
      final options = LinkPreviewOptions(url: url);

      expect(options.media, LinkPreviewMedia.auto);
      expect(options.removed, isFalse);
    });

    test('is a value', () {
      expect(
        LinkPreviewOptions(url: url, media: LinkPreviewMedia.large),
        LinkPreviewOptions(url: url, media: LinkPreviewMedia.large),
      );
      expect(
        LinkPreviewOptions(url: url, media: LinkPreviewMedia.large).hashCode,
        LinkPreviewOptions(url: url, media: LinkPreviewMedia.large).hashCode,
      );
      expect(
        LinkPreviewOptions(url: url),
        isNot(LinkPreviewOptions(url: url, removed: true)),
      );
      expect(
        LinkPreviewOptions(url: url),
        isNot(LinkPreviewOptions(url: url, media: LinkPreviewMedia.small)),
      );
      expect(
        LinkPreviewOptions(url: url),
        isNot(LinkPreviewOptions(url: Uri.parse('https://example.org'))),
      );
    });

    test('copyWith keeps what it is not given', () {
      final options = LinkPreviewOptions(
        url: url,
        media: LinkPreviewMedia.small,
      );

      expect(
        options.copyWith(removed: true),
        LinkPreviewOptions(
          url: url,
          media: LinkPreviewMedia.small,
          removed: true,
        ),
      );
    });
  });

  group('LinkPreviewMedia', () {
    test('has stable written values', () {
      expect(LinkPreviewMedia.auto.value, 'auto');
      expect(LinkPreviewMedia.small.value, 'small');
      expect(LinkPreviewMedia.large.value, 'large');
    });

    test('reads an unknown or missing value as auto', () {
      expect(LinkPreviewMedia.fromValue('small'), LinkPreviewMedia.small);
      expect(LinkPreviewMedia.fromValue('huge'), LinkPreviewMedia.auto);
      expect(LinkPreviewMedia.fromValue(null), LinkPreviewMedia.auto);
    });
  });
}
