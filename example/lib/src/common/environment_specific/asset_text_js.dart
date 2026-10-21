import 'dart:js_interop';

/// The web hook: the text asset at [path], fetched on demand over HTTP.
///
/// The comment chunks are kept out of the bundle (and the service worker) and
/// served as static files from the `web/comments/` link, so the browser loads
/// only the chunks a chat reaches.
Future<String> $loadAssetText(String path) async {
  final webPath = path.replaceFirst('assets/comments/', 'comments/');
  final response = await _$fetch(webPath.toJS).toDart;
  if (!response.ok) {
    throw Exception(
      'Failed to load asset "$path": '
      'HTTP ${response.status} ${response.statusText.toDart}',
    );
  }
  return (await response.text().toDart).toDart;
}

@JS('fetch')
external JSPromise<_Response> _$fetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSString get statusText;
  external JSPromise<JSString> text();
}
