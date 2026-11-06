import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Why a request to Giphy failed, as the callers need to tell it: whether
/// asking again later can help.
///
/// It never carries the request's URL, which holds the API key.
final class GiphyFailure implements Exception {
  /// Creates a failure explained by [message].
  const GiphyFailure(this.message, {required this.transient, this.cause});

  /// What went wrong, for logs.
  final String message;

  /// Offline, timed out, a busy server or a limit: worth repeating later.
  /// Otherwise a refused key, a missing clip or an answer that is not the
  /// documented shape, which repeating unchanged will not fix.
  final bool transient;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() =>
      'GiphyFailure(${transient ? 'transient' : 'permanent'}): $message';
}

/// One GIF of Giphy as this host plays it: the file, and its proportions.
///
/// The file is an MP4 rendition where the API offers one (the video decoder
/// plays it), and the GIF otherwise (the video decoder reads that too). It is
/// the answer's data and not a content descriptor: `GiphyContent` makes the
/// descriptor.
@immutable
final class GiphyClip {
  /// Creates the clip [id], playing from [url], [width] x [height] pixels.
  const GiphyClip({
    required this.id,
    required this.title,
    required this.url,
    required this.width,
    required this.height,
  });

  /// Giphy's id of the GIF.
  final String id;

  /// Its title, which may be empty.
  final String title;

  /// Where the file is.
  final Uri url;

  /// The file's width in pixels.
  final int width;

  /// The file's height in pixels.
  final int height;

  // The renditions to take, the smallest that still looks right in a row of
  // the panel first: a fixed width of 200 px, then smaller.
  static const _renditions = [
    'fixed_width',
    'fixed_width_small',
    'downsized_small',
  ];

  /// The clip [json] describes, or null for an entry without a playable file
  /// or a usable size: such a GIF is left out of the list, not shown broken.
  ///
  /// The API's JSON is read here, at the edge, by pattern and without codegen:
  /// the example takes no `json_serializable`, and only a handful of the
  /// documented fields are read.
  static GiphyClip? tryDecode(Object? json) {
    if (json case {
      'id': final String id,
      'images': final Map<String, Object?> images,
    } when id.isNotEmpty) {
      final title = json['title'] is String ? json['title']! as String : '';
      // The mp4 of the first rendition that has one, else the GIF of the
      // first that has that.
      for (final key in ['mp4', 'url']) {
        for (final name in _renditions) {
          if (images[name]
              case {'width': final String w, 'height': final String h} &&
                  final Map<String, Object?> rendition) {
            final url = rendition[key];
            final width = int.tryParse(w);
            final height = int.tryParse(h);
            if (url is String &&
                url.isNotEmpty &&
                width != null &&
                height != null &&
                width > 0 &&
                height > 0) {
              return GiphyClip(
                id: id,
                title: title.trim(),
                url: Uri.parse(url),
                width: width,
                height: height,
              );
            }
          }
        }
      }
    }
    return null;
  }
}

/// One page of clips and where the next begins.
@immutable
final class GiphyPage {
  /// Creates a page of [clips] followed by the page at [nextOffset], or by
  /// none when it is null.
  const GiphyPage(this.clips, {this.nextOffset});

  /// The clips, in the API's order.
  final List<GiphyClip> clips;

  /// The offset of the next page, or null at the end.
  final int? nextOffset;
}

/// The Giphy API: trending, search, a batch by id, and the download of a
/// clip's file.
///
/// The HTTP client is injected, so the host owns its lifetime and a test hands
/// in a fake; nothing here is global. Every request has a [timeout]. A failure
/// is a [GiphyFailure], never another error, and never mentions the key.
final class GiphyClient {
  /// Creates a client that identifies itself with [apiKey] and sends through
  /// [client].
  GiphyClient({
    required String apiKey,
    required http.Client client,
    this.timeout = const Duration(seconds: 10),
    this.pageSize = 24,
    this.rating = 'g',
  }) : _apiKey = apiKey,
       _client = client;

  static const String _host = 'api.giphy.com';

  // Giphy answers no offset beyond this: the last page it will give.
  static const int _maxOffset = 4999;

  final String _apiKey;
  final http.Client _client;

  /// How long a request may take.
  final Duration timeout;

  /// How many clips a page asks for.
  final int pageSize;

  /// The content rating asked for.
  final String rating;

  /// The trending clips from [offset].
  Future<GiphyPage> trending({int offset = 0}) =>
      _page('/v1/gifs/trending', {'offset': '$offset'}, offset);

  /// The clips found for [query], from [offset].
  Future<GiphyPage> search(String query, {int offset = 0}) =>
      _page('/v1/gifs/search', {'q': query, 'offset': '$offset'}, offset);

  /// The clips with [ids]; one an unknown id is left out.
  Future<List<GiphyClip>> byIds(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const [];
    final body = await _getJson('/v1/gifs', {'ids': list.join(',')});
    return _clips(body);
  }

  /// The bytes of the file at [url], which is not Giphy's API and gets no key.
  Future<Uint8List> download(Uri url) async {
    final response = await _send(() => _client.get(url), 'download');
    return response.bodyBytes;
  }

  Future<GiphyPage> _page(
    String path,
    Map<String, String> query,
    int offset,
  ) async {
    final body = await _getJson(path, {'limit': '$pageSize', ...query});
    final clips = _clips(body);
    final next = switch (body) {
      {'pagination': {'total_count': final int total, 'count': final int n}}
          when n > 0 && offset + n < total && offset + n <= _maxOffset =>
        offset + n,
      _ => null,
    };
    return GiphyPage(clips, nextOffset: next);
  }

  static List<GiphyClip> _clips(Object? body) => switch (body) {
    {'data': final List<Object?> data} => [
      for (final entry in data) ?GiphyClip.tryDecode(entry),
    ],
    _ => throw const GiphyFailure(
      'the answer has no list of clips',
      transient: false,
    ),
  };

  Future<Object?> _getJson(String path, Map<String, String> query) async {
    final uri = Uri.https(_host, path, {
      'api_key': _apiKey,
      'rating': rating,
      ...query,
    });
    final response = await _send(() => _client.get(uri), path);
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw GiphyFailure(
        'the answer of $path is not JSON',
        transient: false,
        cause: error,
      );
    }
  }

  // One request with its timeout, its failures sorted into transient and
  // permanent, and [what] to name it by: never the URL.
  Future<http.Response> _send(
    Future<http.Response> Function() request,
    String what,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException catch (error) {
      throw GiphyFailure('$what timed out', transient: true, cause: error);
    } on http.ClientException catch (error) {
      throw GiphyFailure(
        '$what could not connect',
        transient: true,
        cause: error,
      );
    } on Object catch (error) {
      // dart:io's socket errors are not http's exceptions, and this file takes
      // no dart:io (the example builds for the web).
      throw GiphyFailure('$what failed', transient: true, cause: error);
    }
    final status = response.statusCode;
    if (status >= 200 && status < 300) return response;
    throw GiphyFailure(
      '$what answered $status',
      transient: status == 429 || status >= 500,
    );
  }
}
