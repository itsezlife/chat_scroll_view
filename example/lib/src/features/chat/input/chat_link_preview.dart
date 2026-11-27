import 'dart:async';

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_draft_store.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:listen/listen.dart' as listen;

/// The operations of the `linkPreview` diagnostics events [ChatLinkPreview]
/// emits. The dismissal's own events are `LinkPreviewDismissalOp`'s.
///
/// Closed: an operation is added here with the path that emits it. No event
/// carries text: a URL is reported by its host only.
enum ChatLinkPreviewOp implements DiagnosticOp {
  /// A lookup started (debug): `candidateCount`, `chosenIndex` (the chosen
  /// URL's place among the text's URLs, -1 when none was chosen) and
  /// `chosenHost` (the host of the URL the strip shows).
  resolveStarted,

  /// A lookup found a page (debug): `durationMs`, `pageType` (empty when the
  /// page names none), `hasPhoto`, `hasMedia`.
  resolveLoaded,

  /// A lookup found no page (debug): `durationMs`.
  resolveNone,

  /// A pending lookup was dropped (debug): `reason`, a
  /// [ChatLinkPreviewCancel] name.
  resolveCancelled,

  /// The resolver threw (warning): `errorType`.
  resolveFailed,

  /// The message's preview options changed (debug): `media`, `removed`,
  /// `invertMedia`.
  optionsChanged,

  /// A draft's preview fields came back (debug): `hadOptions`,
  /// `hadDismissal`. A record that cannot be read is the draft store's
  /// `draftDecodeFailed`.
  draftRestored,
}

/// Why [ChatLinkPreview] dropped a pending lookup.
enum ChatLinkPreviewCancel {
  /// The text changed while it was pending.
  textChanged,

  /// The user chose another link.
  chosen,

  /// The strip's cross was taken.
  dismissed,

  /// The chat stopped allowing link previews.
  denied,

  /// The watcher was disposed.
  disposed,

  /// The message was sent.
  sent,
}

/// What the composer's header strip shows: the link and, once the resolver
/// has it, its page.
@immutable
final class ChatLinkPreviewCard {
  /// A card for [url] with [options]; [page] null while the lookup is
  /// pending.
  const ChatLinkPreviewCard({
    required this.url,
    required this.options,
    this.page,
  });

  /// The URL of the text the card is for.
  final Uri url;

  /// The page, or null while the lookup is pending.
  final LinkPreview? page;

  /// The message's choices about the preview.
  final LinkPreviewOptions options;

  /// Whether the lookup has not answered yet.
  bool get isPending => page == null;

  @override
  bool operator ==(Object other) =>
      other is ChatLinkPreviewCard &&
      other.url == url &&
      other.page == page &&
      other.options == options;

  @override
  int get hashCode => Object.hash(url, page, options);

  @override
  String toString() =>
      'ChatLinkPreviewCard(${url.host}, ${isPending ? 'pending' : 'loaded'})';
}

/// Watches the composer's text for links to preview, looks their page up
/// through the host's [LinkPreviewResolver], and keeps the message's preview
/// options.
///
/// ## Reading the text
///
/// A debounced listener that reads the text and writes nothing back: the
/// composer stays blind to link-class detection (no live underline, no
/// entity while typing), and the URLs are found in a copy of the text that
/// is thrown away. A change is read one second after the last keystroke,
/// and at once when the text jumped by more than [jumpLength] characters (a
/// paste) or the caret follows a space or a line break (the URL is
/// finished).
///
/// ## Looking up
///
/// Every URL of the text, in order, goes to the resolver, less the ones the
/// dismissal disables; a URL the user [choose]s goes alone. Every text edit
/// cancels a lookup still pending before the next reading starts another; a
/// lookup that answered stays while the reading finds the same candidates,
/// so typing after a link does not ask again. The strip shows a pending
/// lookup and a loaded page; a lookup that finds no page shows nothing.
///
/// ## Dismissal and availability
///
/// The strip's cross goes to a [LinkPreviewDismissal] under the host's
/// policy, which decides when search comes back. While the chat does not
/// allow link previews ([available] false) nothing is looked up, the card is
/// dropped, and a message with links is sent with its preview `removed`.
final class ChatLinkPreview {
  /// Watches [text], looking pages up through [resolver]; the cross follows
  /// [policy]. [correlation] gives the ids of the events (the chat).
  ChatLinkPreview({
    required ComposerTextController text,
    required LinkPreviewResolver resolver,
    required LinkPreviewDismissalPolicy policy,
    ChatCorrelation Function()? correlation,
  }) : _text = text,
       _resolver = resolver,
       _correlation = correlation,
       dismissal = LinkPreviewDismissal(
         policy: policy,
         correlation: correlation,
       ) {
    _lastText = text.text;
    text.addListener(_onText);
  }

  /// How long after the last keystroke the text is read.
  static const Duration debounce = Duration(seconds: 1);

  /// A change of more than this many characters is read at once.
  static const int jumpLength = 2;

  /// What the strip's cross has turned off.
  final LinkPreviewDismissal dismissal;

  final ComposerTextController _text;
  final LinkPreviewResolver _resolver;
  final ChatCorrelation Function()? _correlation;
  final _card = listen.ValueNotifier<ChatLinkPreviewCard?>(null);
  final _draftChanged = listen.ValueNotifier<int>(0);
  Timer? _timer;
  late String _lastText;
  var _disposed = false;
  var _available = true;

  List<Uri> _urls = const [];
  Uri? _chosen;
  var _media = LinkPreviewMedia.auto;
  var _invertMedia = false;

  // The lookup in flight or answered, and what it was asked; null after a
  // cancel, so the next reading asks again even for the same candidates.
  LinkPreviewRequest? _request;
  List<Uri> _asked = const [];
  final Stopwatch _clock = Stopwatch();

  /// The card to show, or null.
  listen.ValueListenable<ChatLinkPreviewCard?> get card => _card;

  /// Notifies when a field the draft keeps changes: the options,
  /// [invertMedia], the dismissal.
  listen.Listenable get draftChanged => _draftChanged;

  /// Every URL of the text at the last reading, in text order.
  List<Uri> get urls => List.unmodifiable(_urls);

  /// The URL the user chose among [urls], or null for the resolver's pick.
  Uri? get chosenUrl => _chosen;

  /// Whether the message puts its media above its text.
  bool get invertMedia => _invertMedia;

  /// Whether the chat allows link previews now.
  bool get available => _available;

  /// What the draft keeps of the preview.
  ChatLinkPreviewDraft get draft => ChatLinkPreviewDraft(
    options: _card.value?.options,
    invertMedia: _invertMedia,
    dismissal: dismissal.state.isClear ? null : dismissal.state,
  );

  /// The preview the next message carries: the options with the loaded page,
  /// the options alone while the lookup is pending (the receiver resolves
  /// the URL), `removed` when the user dismissed it or the chat denies
  /// previews, and null for a text without links or a link without a page.
  MessageLinkPreview? get outgoing {
    if (_timer != null) _read();
    if (_urls.isEmpty) return null;
    final shown = _card.value;
    if (shown != null) {
      return MessageLinkPreview(options: shown.options, page: shown.page);
    }
    if (_isRemoved) {
      return MessageLinkPreview(
        options: LinkPreviewOptions(
          url: _chosen ?? _urls.first,
          media: _media,
          removed: true,
        ),
      );
    }
    return null;
  }

  bool get _isRemoved =>
      _urls.isNotEmpty && (!_available || !_urls.any(dismissal.allows));

  // --- Commands ------------------------------------------------------------

  /// Makes the chat allow link previews or not.
  ///
  /// Denied: a pending lookup is dropped and the card goes. Allowed again:
  /// the text is read at once, under the dismissal as it stands (a field
  /// dismissed stays dismissed).
  set available(bool value) {
    if (_disposed || value == _available) return;
    _available = value;
    if (value) {
      _read();
    } else {
      _cancel(ChatLinkPreviewCancel.denied);
      _card.value = null;
    }
    _draftChanged.value++;
  }

  /// Chooses [url], one of [urls], as the link to preview: it is looked up
  /// alone. A URL not in the text, or one the dismissal disables, is
  /// ignored.
  void choose(Uri url) {
    if (_disposed) return;
    if (_timer != null) _read();
    if (!_urls.contains(url) || !dismissal.allows(url) || url == _chosen) {
      return;
    }
    _chosen = url;
    _cancel(ChatLinkPreviewCancel.chosen);
    _update();
  }

  /// The strip's cross: the dismissal policy turns the shown link (or the
  /// field) off, and the next allowed link, if any, is looked up.
  void dismiss() {
    final current = _card.value;
    if (_disposed || current == null) return;
    dismissal.dismiss(current.url);
    if (_chosen == current.url) _chosen = null;
    _cancel(ChatLinkPreviewCancel.dismissed);
    _update();
    _draftChanged.value++;
  }

  /// Sets how large the preview's media is drawn.
  void setMedia(LinkPreviewMedia media) {
    if (_disposed || media == _media) return;
    _media = media;
    if (_card.value case final card?) {
      _card.value = ChatLinkPreviewCard(
        url: card.url,
        page: card.page,
        options: card.options.copyWith(media: media),
      );
    }
    _optionsChanged();
  }

  set invertMedia(bool value) {
    if (_disposed || value == _invertMedia) return;
    _invertMedia = value;
    _optionsChanged();
  }

  /// Takes back what a draft kept, after its text is in the field: the
  /// chosen URL and media of [draft]'s options, [invertMedia] and the
  /// dismissal. The text is read at once.
  void restore(ChatLinkPreviewDraft draft) {
    if (_disposed) return;
    if (draft.options case final options?) {
      _chosen = options.url;
      _media = options.media;
    }
    _invertMedia = draft.invertMedia;
    if (draft.dismissal case final state?) dismissal.restore(state);
    _emit(
      ChatEventLevel.debug,
      ChatLinkPreviewOp.draftRestored,
      () => {
        'hadOptions': draft.options != null,
        'hadDismissal': draft.dismissal != null,
      },
    );
    _read();
  }

  /// The message was sent: the dismissal starts over, the pending lookup is
  /// dropped and the options go back to their defaults.
  void sent() {
    if (_disposed) return;
    dismissal.sent();
    _cancel(ChatLinkPreviewCancel.sent);
    _timer?.cancel();
    _timer = null;
    _urls = const [];
    _chosen = null;
    _media = LinkPreviewMedia.auto;
    _invertMedia = false;
    _card.value = null;
    _draftChanged.value++;
  }

  /// Stops watching and drops a pending lookup. Idempotent.
  void dispose() {
    if (_disposed) return;
    _cancel(ChatLinkPreviewCancel.disposed);
    _disposed = true;
    _timer?.cancel();
    _text.removeListener(_onText);
    _card.dispose();
    _draftChanged.dispose();
  }

  // --- Reading -------------------------------------------------------------

  void _onText() {
    final text = _text.text;
    // A caret move notifies too; only an edit is read.
    if (text == _lastText) return;
    final before = _lastText;
    _lastText = text;
    if (dismissal.edited(before, text)) _draftChanged.value++;
    // A pending lookup is for a text that is gone; one that answered stays
    // while the next reading finds the same links.
    if (_request case final request? when !request.value.isTerminal) {
      _cancel(ChatLinkPreviewCancel.textChanged);
    }
    final jumped = (text.length - before.length).abs() > jumpLength;
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
    _timer?.cancel();
    _timer = null;
    if (_disposed) return;
    _urls = _urlsOf(_text.richText);
    if (dismissal.linksRead(_urls)) _draftChanged.value++;
    if (_chosen case final chosen? when !_urls.contains(chosen)) {
      _chosen = null;
    }
    _update();
  }

  /// Looks up what the text and the dismissal allow now, unless that is
  /// what the current lookup was asked.
  void _update() {
    final candidates = _candidates();
    if (candidates.isEmpty) {
      _cancel(ChatLinkPreviewCancel.textChanged);
      _asked = const [];
      _card.value = null;
      return;
    }
    if (_request != null && listEquals(candidates, _asked)) return;
    _cancel(ChatLinkPreviewCancel.textChanged);
    _resolve(candidates);
  }

  List<Uri> _candidates() {
    if (!_available || !dismissal.searchEnabled) return const [];
    if (_chosen case final chosen? when dismissal.allows(chosen)) {
      return [chosen];
    }
    return [
      for (final url in _urls)
        if (dismissal.allows(url)) url,
    ];
  }

  void _resolve(List<Uri> candidates) {
    _asked = candidates;
    _emit(
      ChatEventLevel.debug,
      ChatLinkPreviewOp.resolveStarted,
      () => {
        'candidateCount': candidates.length,
        'chosenIndex': switch (_chosen) {
          final chosen? => _urls.indexOf(chosen),
          null => -1,
        },
        'chosenHost': ChatEvent.clip(candidates.first.host),
      },
    );
    final LinkPreviewRequest request;
    try {
      request = _resolver.resolve(candidates);
    } on Object catch (error, stackTrace) {
      _emit(
        ChatEventLevel.warning,
        ChatLinkPreviewOp.resolveFailed,
        () => {'errorType': ChatEvent.clip(error.runtimeType.toString())},
        error: error,
        stackTrace: stackTrace,
      );
      _card.value = null;
      return;
    }
    _request = request;
    _clock
      ..reset()
      ..start();
    void onState() => _onState(request);
    request.addListener(onState);
    _show(request, candidates);
    if (request.value.isTerminal) {
      request.removeListener(onState);
      _answered(request.value);
    }
  }

  void _onState(LinkPreviewRequest request) {
    if (_disposed || !identical(request, _request)) return;
    if (!request.value.isTerminal) return;
    _show(request, _asked);
    _answered(request.value);
  }

  void _answered(LinkPreviewState state) {
    _clock.stop();
    final durationMs = _clock.elapsedMilliseconds;
    switch (state) {
      case LinkPreviewState$Loaded(:final page):
        _emit(
          ChatEventLevel.debug,
          ChatLinkPreviewOp.resolveLoaded,
          () => {
            'durationMs': durationMs,
            'pageType': ChatEvent.clip(page.type ?? ''),
            'hasPhoto': page.photo != null,
            'hasMedia': page.media != null,
          },
        );
      case LinkPreviewState$None():
        _emit(
          ChatEventLevel.debug,
          ChatLinkPreviewOp.resolveNone,
          () => {'durationMs': durationMs},
        );
      case LinkPreviewState$Pending():
        break;
    }
  }

  void _show(LinkPreviewRequest request, List<Uri> candidates) {
    final previous = _card.value?.options;
    final next = switch (request.value) {
      LinkPreviewState$Pending() => _cardFor(candidates.first, null),
      LinkPreviewState$Loaded(:final page) => _cardFor(
        candidates.contains(page.url) ? page.url : candidates.first,
        page,
      ),
      LinkPreviewState$None() => null,
    };
    _card.value = next;
    if (next?.options != previous) _draftChanged.value++;
  }

  ChatLinkPreviewCard _cardFor(Uri url, LinkPreview? page) =>
      ChatLinkPreviewCard(
        url: url,
        page: page,
        options: LinkPreviewOptions(url: url, media: _media),
      );

  /// Drops the pending lookup, reporting [reason]; a lookup that answered
  /// is only forgotten.
  void _cancel(ChatLinkPreviewCancel reason) {
    final request = _request;
    if (request == null) return;
    _request = null;
    if (request.value.isTerminal) return;
    request.cancel();
    _clock.stop();
    _emit(
      ChatEventLevel.debug,
      ChatLinkPreviewOp.resolveCancelled,
      () => {'reason': reason.name},
    );
  }

  void _optionsChanged() {
    _emit(
      ChatEventLevel.debug,
      ChatLinkPreviewOp.optionsChanged,
      () => {
        'media': _media.value,
        'removed': _isRemoved,
        'invertMedia': _invertMedia,
      },
    );
    _draftChanged.value++;
  }

  void _emit(
    ChatEventLevel level,
    ChatLinkPreviewOp op,
    Map<String, Object> Function() fields, {
    Object? error,
    StackTrace? stackTrace,
  }) => ChatDiagnostics.current.emit(
    level,
    ChatEventCategory.linkPreview,
    op,
    correlation: _correlation?.call() ?? ChatCorrelation.none,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
  );

  /// Every URL of [text], in order and once each, found with a detector
  /// that sees URLs only.
  static List<Uri> _urlsOf(RichText text) {
    final found = EntityDetection.apply(text, DetectionPolicy.urlsOnly);
    final urls = <Uri>[];
    for (final entity in found.entities) {
      if (entity.kind case EntityKind$Link(:final url)) {
        if (Uri.tryParse(url) case final uri?
            when uri.isAbsolute && !urls.contains(uri)) {
          urls.add(uri);
        }
      }
    }
    return urls;
  }
}
