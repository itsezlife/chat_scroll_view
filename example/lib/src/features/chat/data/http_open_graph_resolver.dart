import 'dart:async';
import 'dart:convert';

import 'package:chat_scroll_view_example/src/features/chat/input/chat_link_preview.dart'
    show ChatLinkPreviewOp;
import 'package:content_model/content_model.dart';
import 'package:http/http.dart' as http;

/// A link preview resolver that fetches each candidate page itself and
/// reads its Open Graph tags (`og:title`, `og:description`, `og:site_name`,
/// `og:type`, `og:url`), falling back to the page's `<title>` and its
/// `description` meta tag.
///
/// It fetches from the client, which is the host's call to make, not a
/// package's: the linked site sees the user's address, and the request
/// follows the site's redirects wherever they lead. A host with a backend
/// that has the pages passes that backend's resolver instead.
///
/// The candidates are tried in order; the first page that answers with
/// HTML and at least a title or a description is the preview. A request
/// that fails (it throws, times out, or answers with an error status) moves
/// to the next candidate and reports `linkPreview` / `resolveFailed`
/// (warning, `errorType`, the URL's host only). No candidate with a page
/// ends at none.
///
/// The page's image is not taken: the example's asset pipeline has no
/// fetch route for an arbitrary web address, so a card would keep a
/// placeholder for ever.
final class HttpOpenGraphResolver implements LinkPreviewResolver {
  /// A resolver that fetches through [client], for the chat [chatId] (on
  /// every event).
  ///
  /// [timeout] bounds each fetch; [maxBytes] is how much of a page is read
  /// (the tags are in its head).
  HttpOpenGraphResolver({
    required http.Client client,
    this.chatId,
    this.timeout = const Duration(seconds: 10),
    this.maxBytes = 256 * 1024,
  }) : _client = client;

  final http.Client _client;

  /// The chat the events name; null for none.
  final String? chatId;

  /// How long one fetch may take.
  final Duration timeout;

  /// How many bytes of a page are read.
  final int maxBytes;

  @override
  LinkPreviewRequest resolve(List<Uri> candidates) {
    var cancelled = false;
    final completer = LinkPreviewCompleter(onCancel: () => cancelled = true);
    unawaited(() async {
      for (final url in candidates) {
        if (cancelled) return;
        if (url.scheme != 'http' && url.scheme != 'https') continue;
        final page = await _fetch(url);
        if (page != null) {
          completer.complete(page);
          return;
        }
      }
      completer.complete(null);
    }());
    return completer.request;
  }

  Future<LinkPreview?> _fetch(Uri url) async {
    try {
      final request = http.Request('GET', url)
        ..headers['accept'] = 'text/html,application/xhtml+xml';
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _discard(url, response);
        _failed(url, 'status${response.statusCode}');
        return null;
      }
      final type = response.headers['content-type'] ?? '';
      if (!type.contains('html')) {
        _discard(url, response);
        return null;
      }
      final bytes = await _head(response.stream).timeout(timeout);
      return OpenGraphPage.parse(
        utf8.decode(bytes, allowMalformed: true),
        url: response.request?.url ?? url,
      );
    } on Object catch (error) {
      _failed(url, error.runtimeType.toString());
      return null;
    }
  }

  // The first [maxBytes] of [stream].
  Future<List<int>> _head(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length >= maxBytes) break;
    }
    return bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
  }

  // Reads off the body of a response the resolver does not use, so the
  // connection is released. The candidate is already passed over; a body
  // that fails on the way is still reported (`discard` and its error type).
  void _discard(Uri url, http.StreamedResponse response) => unawaited(
    response.stream.drain<void>().catchError(
      (Object error) => _failed(url, 'discard${error.runtimeType}'),
    ),
  );

  void _failed(Uri url, String errorType) => ChatDiagnostics.current.emit(
    ChatEventLevel.warning,
    ChatEventCategory.linkPreview,
    ChatLinkPreviewOp.resolveFailed,
    correlation: ChatCorrelation(chatId: chatId),
    fields: () => {'errorType': errorType, 'host': url.host},
  );
}

/// The Open Graph reading of a page's HTML, as a [LinkPreview].
abstract final class OpenGraphPage {
  static final RegExp _meta = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
  static final RegExp _attribute = RegExp(
    r'''([a-zA-Z:-]+)\s*=\s*("([^"]*)"|'([^']*)')''',
  );
  static final RegExp _title = RegExp(
    '<title[^>]*>([^<]*)</title>',
    caseSensitive: false,
  );

  /// The page [html] fetched from [url], or null when it names neither a
  /// title nor a description.
  static LinkPreview? parse(String html, {required Uri url}) {
    final tags = <String, String>{};
    for (final match in _meta.allMatches(html)) {
      final attributes = <String, String>{
        for (final attribute in _attribute.allMatches(match[0]!))
          attribute[1]!.toLowerCase(): attribute[3] ?? attribute[4] ?? '',
      };
      final name = attributes['property'] ?? attributes['name'];
      final content = attributes['content'];
      if (name == null || content == null) continue;
      tags.putIfAbsent(name.toLowerCase(), () => _decode(content.trim()));
    }
    final title =
        _nonEmpty(tags['og:title']) ??
        _nonEmpty(switch (_title.firstMatch(html)) {
          final match? => _decode(match[1]!.trim()),
          null => null,
        });
    final description =
        _nonEmpty(tags['og:description']) ?? _nonEmpty(tags['description']);
    if (title == null && description == null) return null;
    final canonical = switch (tags['og:url']) {
      final value? => switch (Uri.tryParse(value)) {
        final uri? when uri.hasScheme => uri,
        _ => url,
      },
      null => url,
    };
    return LinkPreview(
      url: canonical,
      displayUrl: canonical.host,
      type: _nonEmpty(tags['og:type']),
      siteName: _nonEmpty(tags['og:site_name']) ?? canonical.host,
      title: title,
      description: switch (description) {
        final text? => RichText.plain(text),
        null => RichText.empty,
      },
    );
  }

  static String? _nonEmpty(String? value) => switch (value) {
    final text? when text.isNotEmpty => text,
    _ => null,
  };

  static String _decode(String text) => text
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}
