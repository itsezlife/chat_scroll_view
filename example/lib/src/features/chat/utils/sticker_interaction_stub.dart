import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatInlineGesture, ChatStickerActivated;
import 'package:content_model/content_model.dart'
    show ContentKey, ContentKey$Unicode;
import 'package:flutter/foundation.dart';

/// What the host would hand the network for one batch of direct taps on an
/// emoji sticker: the typing-class action of the reference clients, whose
/// shape is `sendMessageEmojiInteraction(emoticon, msg_id, interaction)` with
/// `interaction` the JSON text in [interaction].
@immutable
final class StickerBroadcast {
  /// A batch of interactions with the sticker of [messageId], whose emoji is
  /// [emoticon].
  const StickerBroadcast({
    required this.messageId,
    required this.emoticon,
    required this.interaction,
  });

  /// The message the taps were on.
  final int messageId;

  /// The emoji as the sender wrote it (unicode), or the custom emoji's key.
  final String emoticon;

  /// `{"v":1,"a":[{"i":n,"t":seconds}, ...]}`: `i` the 1-based index of the
  /// effect that played, `t` the seconds since the first tap of the batch.
  final String interaction;

  @override
  String toString() =>
      'StickerBroadcast(emoticon: $emoticon, msg_id: $messageId, '
      'interaction: $interaction)';
}

/// The example's stand-in for broadcasting a direct tap on an emoji sticker
/// to the peer, so a real host can add the network and the full-screen effect
/// without changing the body.
///
/// It takes the `ChatStickerActivated` the viewport reports for each tap,
/// batches them the way the reference clients do and hands each batch to
/// [onBroadcast] as the [StickerBroadcast] that would be sent. It sends
/// nothing and draws no effect; the example only shows the batch.
///
/// ## Host-owned values
///
/// Both numbers are the host's, not the viewport's:
///
/// - [debounce], 500 ms: a batch is sent this long after its last tap (the
///   Android client re-arms a timer on each tap; iOS sends once, 1.0 s after
///   the first tap).
/// - [window], 1.0 s: a batch is sent no later than this after its first tap.
///   Desktop discards an incoming entry whose offset is outside `[0, 1]` s or
///   not greater than the one before, so an open-ended Android debounce can
///   emit what Desktop drops; closing the batch at the window keeps every
///   offset within it. A tap after the window starts the next batch.
///
/// A tap on another message sends the pending batch at once. Offsets come
/// from the taps' own monotonic `tapTime`, never from a clock read here, so
/// they are the taps' and not the handler's. The animation index is chosen
/// at random from [animationCount] effects of the emoji, with the [random]
/// source injected. The gates a host owns are one callback, [canInteract]:
/// the chat is a private chat with another user, not Saved Messages, not a
/// secret chat, and the message is sent.
final class StickerInteractionStub {
  /// Creates the stub; [onBroadcast] receives every batch.
  StickerInteractionStub({
    required this.onBroadcast,
    required this.animationCount,
    required this.canInteract,
    Random? random,
  }) : _random = random ?? Random();

  /// A batch is sent this long after its last tap.
  static const Duration debounce = Duration(milliseconds: 500);

  /// A batch is sent no later than this after its first tap.
  static const Duration window = Duration(seconds: 1);

  /// Receives each batch that would be broadcast.
  final void Function(StickerBroadcast broadcast) onBroadcast;

  /// How many effects the emoji has (the animated-emoji pack's); 0 for one
  /// with none, which is not an interaction.
  final int Function(ContentKey emoji) animationCount;

  /// Whether the chat takes interactions at all.
  final bool Function() canInteract;

  final Random _random;
  _Batch? _batch;
  Timer? _debounceTimer;
  Timer? _windowTimer;

  /// Takes a sticker gesture and says whether it is an interaction this
  /// handler took: a tap on an emoji with an effect in a chat that allows
  /// it. A long press is not.
  bool onActivated(ChatStickerActivated activation) {
    if (activation.gesture != ChatInlineGesture.tap || !canInteract()) {
      return false;
    }
    final count = animationCount(activation.content);
    if (count <= 0) return false;

    final current = _batch;
    if (current != null &&
        (current.messageId != activation.messageId ||
            activation.tapTime - current.first >= window)) {
      _flush();
    }
    final batch = _batch ??= _start(activation);
    final offset = activation.tapTime - batch.first;
    // Offsets strictly increase: a tap at the instant of the last is the same
    // tap to the peer.
    if (batch.entries.isEmpty || offset > batch.entries.last.offset) {
      batch.entries.add((index: _random.nextInt(count) + 1, offset: offset));
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _flush);
    return true;
  }

  _Batch _start(ChatStickerActivated activation) {
    _windowTimer = Timer(window, _flush);
    return _Batch(
      messageId: activation.messageId,
      emoticon: switch (activation.content) {
        ContentKey$Unicode(:final sequence) => sequence,
        final other => other.encoded,
      },
      first: activation.tapTime,
    );
  }

  void _flush() {
    final batch = _batch;
    _batch = null;
    _debounceTimer?.cancel();
    _windowTimer?.cancel();
    _debounceTimer = _windowTimer = null;
    if (batch == null || batch.entries.isEmpty) return;
    onBroadcast(
      StickerBroadcast(
        messageId: batch.messageId,
        emoticon: batch.emoticon,
        interaction: jsonEncode({
          'v': 1,
          'a': [
            for (final e in batch.entries)
              {'i': e.index, 't': e.offset.inMilliseconds / 1000},
          ],
        }),
      ),
    );
  }

  /// Drops a pending batch: nothing is sent after this.
  void dispose() {
    _debounceTimer?.cancel();
    _windowTimer?.cancel();
    _debounceTimer = _windowTimer = null;
    _batch = null;
  }
}

final class _Batch {
  _Batch({
    required this.messageId,
    required this.emoticon,
    required this.first,
  });

  final int messageId;
  final String emoticon;
  final Duration first;
  final List<({int index, Duration offset})> entries = [];
}
