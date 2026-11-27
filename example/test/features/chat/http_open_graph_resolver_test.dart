/// The example's Open Graph resolver over a fake HTTP client: the
/// resolver contract, what it reads from a page, and how a failed fetch is
/// reported.
library;

import 'package:chat_scroll_view_example/src/features/chat/data/http_open_graph_resolver.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_link_preview.dart'
    show ChatLinkPreviewOp;
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _page = '''
<html><head>
<title>Fallback title</title>
<meta property="og:title" content="Dart &amp; Flutter">
<meta property='og:description' content="Fast apps on any platform.">
<meta property="og:site_name" content="Dart">
<meta property="og:type" content="article">
<meta property="og:url" content="https://dart.dev/overview">
</head><body>private body text</body></html>
''';

final _withPage = Uri.parse('https://dart.dev/overview?secret=1');
final _broken = Uri.parse('https://down.example/path/to/page');
final _plain = Uri.parse('https://files.example/notes.txt');
final _empty = Uri.parse('https://empty.example/');

http.Client _client() => MockClient((request) async {
  final url = request.url;
  if (url.host == _withPage.host) {
    return http.Response(
      _page,
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }
  if (url.host == _broken.host) return http.Response('', 503);
  if (url.host == _plain.host) {
    return http.Response(
      'just text',
      200,
      headers: {'content-type': 'text/plain'},
    );
  }
  if (url.host == _empty.host) {
    return http.Response(
      '<html><head></head></html>',
      200,
      headers: {'content-type': 'text/html'},
    );
  }
  throw http.ClientException('no route', url);
});

Future<LinkPreviewState> _ended(LinkPreviewRequest request) async {
  for (var i = 0; i < 50 && !request.value.isTerminal; i++) {
    await pumpEventQueue();
  }
  return request.value;
}

void main() {
  LinkPreviewResolverContract.run(
    () async => LinkPreviewResolverHarness(
      resolver: HttpOpenGraphResolver(client: _client(), chatId: 'chat-1'),
      withPage: [_withPage],
      withoutPage: [_plain, _empty],
      settle: pumpEventQueue,
    ),
  );

  test('reads the Open Graph tags of the page', () async {
    final resolver = HttpOpenGraphResolver(client: _client());

    final state = await _ended(resolver.resolve([_withPage]));

    final page = (state as LinkPreviewState$Loaded).page;
    expect(page.url, Uri.parse('https://dart.dev/overview'));
    expect(page.displayUrl, 'dart.dev');
    expect(page.title, 'Dart & Flutter');
    expect(page.description.plain, 'Fast apps on any platform.');
    expect(page.siteName, 'Dart');
    expect(page.type, 'article');
    // No fetch route for a web image: the card shows no photo.
    expect(page.photo, isNull);
  });

  test('falls back to the title and the description tag', () {
    final page = OpenGraphPage.parse(
      '<title>Only a title</title> '
      '<meta name="description" content="And a description">',
      url: Uri.parse('https://site.example/a'),
    )!;

    expect(page.title, 'Only a title');
    expect(page.description.plain, 'And a description');
    expect(page.siteName, 'site.example');
    expect(page.url, Uri.parse('https://site.example/a'));
  });

  test('a page without a title or a description is no preview', () {
    expect(
      OpenGraphPage.parse(
        '<meta property="og:type" content="website">',
        url: Uri.parse('https://site.example/'),
      ),
      isNull,
    );
  });

  test('tries the candidates in order and reports a failed fetch by its host '
      'only', () async {
    final diagnostics = RecordingDiagnostics.install();
    final resolver = HttpOpenGraphResolver(client: _client(), chatId: 'c-9');

    final state = await _ended(resolver.resolve([_broken, _withPage]));

    expect(state, isA<LinkPreviewState$Loaded>());
    final failed = diagnostics.events
        .where((event) => event.op == ChatLinkPreviewOp.resolveFailed)
        .toList();
    expect(failed, hasLength(1));
    final event = failed.single;
    expect(event.level, ChatEventLevel.warning);
    expect(event.category, ChatEventCategory.linkPreview);
    expect(event.correlation.chatId, 'c-9');
    expect(event.fields, {'errorType': 'status503', 'host': 'down.example'});
    expect(event.toString(), isNot(contains('/path/to/page')));
  });

  test('a client that throws is reported and ends at none', () async {
    final diagnostics = RecordingDiagnostics.install();
    final resolver = HttpOpenGraphResolver(client: _client());

    final state = await _ended(
      resolver.resolve([Uri.parse('https://nowhere.example/x?q=1')]),
    );

    expect(state, LinkPreviewState.none);
    expect(diagnostics.events.single.fields, {
      'errorType': 'ClientException',
      'host': 'nowhere.example',
    });
  });

  test('a scheme it does not fetch is skipped', () async {
    final resolver = HttpOpenGraphResolver(client: _client());

    final state = await _ended(resolver.resolve([Uri.parse('mailto:a@b.c')]));

    expect(state, LinkPreviewState.none);
  });
}
