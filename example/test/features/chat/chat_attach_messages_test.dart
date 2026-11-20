import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_attach.dart';
import 'package:content_model/content_model.dart' as content;
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_core/mpx_core.dart' show MediaDimensions;

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
}
