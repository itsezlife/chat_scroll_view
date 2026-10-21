import 'dart:async';

import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:listen/listen.dart' as listen;
import 'package:meta/meta.dart';

/// The link the composer's header offers a preview of.
///
/// A stub of the card a real host fills from its backend (title, description,
/// image): fetching, a `no_webpage` choice and picking among several URLs are
/// the host's and not this demo's.
@immutable
final class ChatLinkPreviewCard {
  /// A preview of [url].
  const ChatLinkPreviewCard(this.url);

  /// The URL as detection found it.
  final String url;

  /// The page's name, as far as the URL says: its host.
  String get title => Uri.tryParse(url)?.host ?? url;

  @override
  bool operator ==(Object other) =>
      other is ChatLinkPreviewCard && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Watches the composer's text for a URL to preview.
///
/// A debounced listener that reads the text and writes nothing back: the
/// composer stays blind to link-class detection (no live underline, no entity
/// while typing), and the URL is found in a copy of the text
/// that is thrown away. The timing is the reference client's: a change is read
/// one second after the last keystroke, and at once when the text jumped by
/// more than [jumpLength] characters (a paste) or the caret follows a space or
/// a line break (the URL is finished).
///
/// Dismissing the card keeps the URL it showed from coming back until a
/// different one is first.
final class ChatLinkPreview {
  /// Watches [text].
  ChatLinkPreview({required ComposerTextController text}) : _text = text {
    _lastText = text.text;
    text.addListener(_onText);
  }

  /// How long after the last keystroke the text is read.
  static const Duration debounce = Duration(seconds: 1);

  /// A change of more than this many characters is read at once.
  static const int jumpLength = 2;

  final ComposerTextController _text;
  final _card = listen.ValueNotifier<ChatLinkPreviewCard?>(null);
  Timer? _timer;
  late String _lastText;
  String? _dismissedUrl;
  var _disposed = false;

  /// The card to show, or null.
  listen.ValueListenable<ChatLinkPreviewCard?> get card => _card;

  /// Hides the card; its URL stays hidden until another URL is first.
  void dismiss() {
    final current = _card.value;
    if (_disposed || current == null) return;
    _dismissedUrl = current.url;
    _card.value = null;
  }

  void _onText() {
    final text = _text.text;
    // A caret move notifies too; only an edit is read.
    if (text == _lastText) return;
    final jumped = (text.length - _lastText.length).abs() > jumpLength;
    _lastText = text;
    _timer?.cancel();
    if (jumped || _followsSpace(text)) {
      _timer = null;
      _read();
    } else {
      _timer = Timer(debounce, _read);
    }
  }

  bool _followsSpace(String text) {
    final caret = _text.selection.baseOffset;
    if (caret < 1 || caret > text.length) return false;
    final unit = text.codeUnitAt(caret - 1);
    return unit == 0x20 || unit == 0x0A || unit == 0xA0;
  }

  void _read() {
    _timer = null;
    if (_disposed) return;
    final url = _firstUrl(_text.richText);
    if (url != _dismissedUrl) _dismissedUrl = null;
    _card.value = url == null || url == _dismissedUrl
        ? null
        : ChatLinkPreviewCard(url);
  }

  /// The first URL of [text], found with a detector that sees URLs only.
  static String? _firstUrl(RichText text) {
    final found = EntityDetection.apply(text, DetectionPolicy.urlsOnly);
    for (final entity in found.entities) {
      if (entity.kind case EntityKind$Link(:final url)) return url;
    }
    return null;
  }

  /// Stops watching. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _text.removeListener(_onText);
    _card.dispose();
  }
}
