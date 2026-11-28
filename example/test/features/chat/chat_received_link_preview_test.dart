import 'package:chat_scroll_view_example/src/features/chat/data/chat_received_link_preview.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Uri.parse('https://a.example/x');
  final page = LinkPreview(url: url, title: 'T');

  Map<String, Object?> payload(MessageLinkPreview? preview) {
    final json = <String, Object?>{'body': 'see $url'};
    LinkPreviewWire.write(json, linkPreview: preview);
    return json;
  }

  final body = RichText.plain('see $url');

  test('a page that arrived is drawn', () {
    final preview = MessageLinkPreview(
      options: LinkPreviewOptions(url: url),
      page: page,
    );

    expect(
      ChatReceivedLinkPreview.read(payload(preview), body: body),
      ChatReceivedLinkPreview.show(preview),
    );
  });

  test('a field without a page is looked up by its URL', () {
    final options = LinkPreviewOptions(url: url, media: LinkPreviewMedia.large);

    expect(
      ChatReceivedLinkPreview.read(
        payload(MessageLinkPreview(options: options)),
        body: body,
      ),
      ChatReceivedLinkPreview.resolve([url], options: options),
    );
  });

  test('removed shows nothing, page or not', () {
    expect(
      ChatReceivedLinkPreview.read(
        payload(
          MessageLinkPreview(
            options: LinkPreviewOptions(url: url, removed: true),
            page: page,
          ),
        ),
        body: body,
      ),
      ChatReceivedLinkPreview.none,
    );
  });

  test('no field shows nothing unless the host flag is on', () {
    expect(
      ChatReceivedLinkPreview.read(payload(null), body: body),
      ChatReceivedLinkPreview.none,
    );
    expect(
      ChatReceivedLinkPreview.read(
        payload(null),
        body: body,
        resolveWithoutField: true,
      ),
      ChatReceivedLinkPreview.resolve([url]),
    );
    expect(
      ChatReceivedLinkPreview.read(
        payload(null),
        body: const RichText.plain('no links'),
        resolveWithoutField: true,
      ),
      ChatReceivedLinkPreview.none,
    );
  });
}
