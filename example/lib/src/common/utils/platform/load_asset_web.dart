import 'dart:js_interop';

/// Web — fetch on demand via HTTP (assets excluded from service worker).
/// Assets are served as static files from web/comments/ symlink.
Future<String> loadAsset(String path) async {
  final webPath = path.replaceFirst('assets/comments/', 'comments/');
  final response = await _jsFetch(webPath.toJS).toDart;
  if (!response.ok) {
    throw Exception(
      'Failed to load asset "$path": '
      'HTTP ${response.status} ${response.statusText.toDart}',
    );
  }
  return (await response.text().toDart).toDart;
}

@JS('fetch')
external JSPromise<_Response> _jsFetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  external bool get ok;
  external int get status;
  external JSString get statusText;
  external JSPromise<JSString> text();
}
