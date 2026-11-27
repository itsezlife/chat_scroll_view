import 'dart:ui' show Rect;

import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:meta/meta.dart';

/// The one-shot send origin: the rect an outgoing item was picked from, or
/// null when there is none (or it was already handed out).
///
/// Declared here so that the host wires its outbox's `takeSendOrigin` in one
/// line and neither package depends on the other.
typedef MediaSendOrigin = Rect? Function(MediaItemId id);

/// What the chat remembers about one media item.
@immutable
final class MediaItemState {
  /// An item's state; the default is a fresh item, spoiler hidden.
  const MediaItemState({this.spoilerRevealed = false});

  /// Whether the viewer revealed the item's spoiler.
  final bool spoilerRevealed;

  @override
  bool operator ==(Object other) =>
      other is MediaItemState && other.spoilerRevealed == spoilerRevealed;

  @override
  int get hashCode => Object.hash(MediaItemState, spoilerRevealed);
}

/// What a chat's media items remember while it is open: `MediaItemId` to
/// [MediaItemState].
///
/// Headless and not persisted: a new state starts with every spoiler hidden,
/// so re-entering a chat hides them again. The host owns one per chat and
/// disposes it; a disposed state asserts on use. Cells reach it through
/// `MessageMediaStateScope`.
final class MessageMediaState {
  /// A state with every item at its default.
  ///
  /// [sendOrigin] is the host's one-shot lookup of an outgoing item's origin
  /// rect (usually its outbox's `takeSendOrigin`).
  MessageMediaState({MediaSendOrigin? sendOrigin}) : _sendOrigin = sendOrigin;

  final MediaSendOrigin? _sendOrigin;
  final Map<MediaItemId, ValueNotifier<MediaItemState>> _items = {};
  bool _disposed = false;

  /// The state of [id]; notifies only when that item's state changes.
  ///
  /// Items are independent: a change to another id does not notify it.
  ValueListenable<MediaItemState> of(MediaItemId id) {
    _assertAlive();
    return _notifier(id);
  }

  /// Whether the spoiler of [id] is revealed.
  bool isSpoilerRevealed(MediaItemId id) {
    _assertAlive();
    return _items[id]?.value.spoilerRevealed ?? false;
  }

  /// Reveals the spoiler of [id]; revealing a revealed one does nothing.
  void revealSpoiler(MediaItemId id) {
    _assertAlive();
    _notifier(id).value = const MediaItemState(spoilerRevealed: true);
  }

  /// Hands out the send origin of [id] once, or null when there is none.
  ///
  /// Asks the host's lookup, which forgets the origin it returns.
  Rect? takeSendOrigin(MediaItemId id) {
    _assertAlive();
    return _sendOrigin?.call(id);
  }

  /// Releases the item notifiers; the state is unusable afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final notifier in _items.values) {
      notifier.dispose();
    }
    _items.clear();
  }

  ValueNotifier<MediaItemState> _notifier(MediaItemId id) =>
      _items.putIfAbsent(id, () => ValueNotifier(const MediaItemState()));

  void _assertAlive() {
    assert(!_disposed, 'MessageMediaState was disposed.');
  }
}
