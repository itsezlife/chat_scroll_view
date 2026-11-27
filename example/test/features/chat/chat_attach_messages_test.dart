import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/sent_documents.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_attach.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart' as content;
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

SendPlan$Ready _plan(
  List<AttachItem> items, {
  AttachPolicy policy = const AttachPolicy.android(),
  String caption = '',
}) =>
    planSend(
          SendRequest(items: items, caption: content.RichText.plain(caption)),
          policy,
          const AttachLimits(),
        )
        as SendPlan$Ready;

void main() {
  test('12 photos make two messages, the caption on the first', () {
    final texts = ChatAttachMessages.of(
      _plan([
        for (var i = 0; i < 12; i++) AttachItems.photo('p$i'),
      ], caption: 'hello'),
    );
    expect(texts, hasLength(2));
    expect(texts.first.split('\n'), hasLength(11));
    expect(texts.first.split('\n')[1], 'hello');
    expect(texts.last.split('\n'), hasLength(2));
  });

  test('the web sends a leading caption as text', () {
    final texts = ChatAttachMessages.of(
      _plan(
        [for (var i = 0; i < 12; i++) AttachItems.photo('p$i')],
        policy: const AttachPolicy.web(),
        caption: 'hi',
      ),
    );
    expect(texts, hasLength(3));
    expect(texts.first, 'hi');
  });

  test('a prepared photo shows its prepared size', () {
    final photo = AttachItems.photo('p');
    final texts = ChatAttachMessages.of(
      _plan([photo]),
      prepared: {
        photo.id: const PreparedMedia(
          kind: PreparedKind.photo,
          path: '/out/p.jpg',
          isOriginal: false,
          byteSize: 100,
          dimensions: MediaDimensions(1280, 960),
        ),
      },
    );
    expect(texts.single, '🖼 p 1280×960');
  });

  test('a file is a paperclip line', () {
    expect(ChatAttachMessages.of(_plan([AttachItems.file('doc')])), [
      '📎 doc.pdf',
    ]);
  });

  group('with the host\'s sent documents', () {
    test('a file from disk is sent as a document row, which the host then '
        'knows and serves in place', () async {
      final known = <content.ContentDescriptor>[];
      final documents = SentDocuments(know: known.add);
      const drawing = AttachItem(
        id: AttachItemId('d1'),
        source: AttachSource.file('/files/plan.svg'),
        kind: AttachKind.file,
        facts: AttachFacts(
          name: 'plan.svg',
          mimeType: 'image/svg+xml',
          byteSize: 900,
        ),
      );

      final texts = ChatAttachMessages.of(
        _plan([drawing]),
        documents: documents,
      );

      expect(texts, ['![plan.svg](file:d1)']);
      final document = documents.document('d1')!;
      expect(document.name, 'plan.svg');
      expect(document.byteSize, 900);
      expect(known.single.key, document.key);
      expect(known.single.mediaForm, content.MediaForm.vectorImage);
      final route = documents.route(FakeFetcher());
      expect(route.needsDownload(document.key.mediaKey), isFalse);
      final fetched = await route.fetch(
        FetchRequest(
          descriptor: known.single.mediaDescriptor!,
          part: FetchPart.content,
          priority: AssetPriority.visible,
          cancellation: CancellationToken(),
        ),
      );
      expect(fetched, isA<FetchedFile>());
      expect((fetched as FetchedFile).path, '/files/plan.svg');
    });

    test('a file of no path (a web blob) stays a paperclip line', () {
      final documents = SentDocuments(know: (_) {});
      const blob = AttachItem(
        id: AttachItemId('b1'),
        source: AttachSource.blob('blob:1'),
        kind: AttachKind.file,
        facts: AttachFacts(name: 'a.svg'),
      );

      expect(ChatAttachMessages.of(_plan([blob]), documents: documents), [
        '📎 a.svg',
      ]);
      expect(documents.document('b1'), isNull);
    });
  });
}
