import 'dart:js_interop';

/// Web — fetch on demand via HTTP (assets excluded from service worker).
/// Assets are served as static files from web/comments/ symlink.
Future<String> loadAsset(String path) async {
  final webPath = path.replaceFirst('assets/book/', 'comments/');
  final response = await _jsFetch(webPath.toJS).toDart;
  return (await response.text().toDart).toDart;
}

@JS('fetch')
external JSPromise<_Response> _jsFetch(JSString url);

extension type _Response(JSObject _) implements JSObject {
  external JSPromise<JSString> text();
}
