/// The media of the user's own outgoing messages, before the server has
/// them: each item's key names it one-to-one as a content key (so a cell
/// reads its upload by it), and its picture is fetched from where the item
/// came from (a library asset, a capture, a file).
///
/// **Seam:** `DemoOutgoingMedia`'s keys and its fetch route over a
/// recording fetcher.
library;

import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outgoing_media.dart';
import 'package:content_assets/content_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';

final class _Recording implements ContentFetcher {
  final List<FetchRequest> requests = [];

  @override
  Future<FetchedContent> fetch(FetchRequest request) async {
    requests.add(request);
    return const FetchedContent.file('/elsewhere');
  }

  @override
  bool needsDownload(MediaKey key) => true;
}

FetchRequest _request(MediaKey key, {FetchPart part = FetchPart.content}) =>
    FetchRequest(
      descriptor: MediaDescriptor(
        key: key,
        kind: MediaKind.still,
        dimensions: const MediaDimensions(4, 3),
      ),
      part: part,
      priority: AssetPriority.visible,
      cancellation: CancellationToken(),
    );

void main() {
  late DemoOutgoingMedia media;
  late _Recording otherwise;
  late ContentFetcher route;

  setUp(() {
    media = DemoOutgoingMedia();
    otherwise = _Recording();
    route = media.route(otherwise);
  });

  test('a minted key is new each time and names its content key back', () {
    final a = media.mint();
    final b = media.mint();

    expect(a, isNot(b));
    expect(DemoOutgoingMedia.isOutgoing(a), isTrue);
    expect(a.contentKey, isNotNull);
    expect(a.contentKey!.mediaKey, a);
  });

  test('an item from a key is fetched as that key', () async {
    final key = media.mint();
    final capture = MediaKey.local('00000000-0000-4000-8000-000000000001');
    media.know(key, DemoOutgoingSource.key(capture));

    await route.fetch(_request(key));

    expect(otherwise.requests.single.descriptor.key, capture);
    expect(
      otherwise.requests.single.descriptor.dimensions,
      const MediaDimensions(4, 3),
    );
  });

  test('an item from a file is read from it, its thumbnail asked on', () async {
    final key = media.mint();
    media.know(key, const DemoOutgoingSource.file('/picked/photo.jpg'));

    final content = await route.fetch(_request(key));
    expect(content, isA<FetchedContent>());
    expect(otherwise.requests, isEmpty);
    expect(route.needsDownload(key), isFalse);
  });

  test('an outgoing key nothing is known for fails for good', () async {
    final key = media.mint();

    await expectLater(route.fetch(_request(key)), throwsA(isA<FetchFailure>()));
    expect(otherwise.requests, isEmpty);
  });

  test('any other key goes on', () async {
    const other = MediaKey.remote('server-1');

    await route.fetch(_request(other));

    expect(otherwise.requests.single.descriptor.key, other);
    expect(route.needsDownload(other), isTrue);
  });

  test('a source reads back from its stored form', () {
    const file = DemoOutgoingSource.file('/a b/c.jpg');
    final key = DemoOutgoingSource.key(
      MediaKey.local('00000000-0000-4000-8000-000000000002'),
    );

    expect(DemoOutgoingSource.parse(file.encoded), file);
    expect(DemoOutgoingSource.parse(key.encoded), key);
    expect(() => DemoOutgoingSource.parse('nope'), throwsFormatException);
  });
}
