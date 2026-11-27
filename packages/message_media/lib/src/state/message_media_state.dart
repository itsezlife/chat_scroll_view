import 'dart:ui' show Offset, Rect;

import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:meta/meta.dart';

/// The one-shot send origin: the rect an outgoing item was picked from, or
/// null when there is none (or it was already handed out).
///
/// Declared here so that the host wires its outbox's `takeSendOrigin` in one
/// line and neither package depends on the other.
typedef MediaSendOrigin = Rect? Function(MediaItemId id);

/// A mounted view's answer to where one of its items is drawn, in global
/// coordinates, or null for an item it does not show.
typedef MediaOriginRect = Rect? Function(MediaItemId id);

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
  final Map<MediaItemId, Offset> _revealOrigins = {};
  final List<MediaOriginRect> _origins = [];
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
  ///
  /// [at] is where the reveal starts in the item's cell (the touch point,
  /// in the cell's coordinates); the cell takes it once
  /// ([takeRevealOrigin]) and starts from its centre without one.
  void revealSpoiler(MediaItemId id, {Offset? at}) {
    _assertAlive();
    final notifier = _notifier(id);
    if (notifier.value.spoilerRevealed) return;
    if (at case final origin?) _revealOrigins[id] = origin;
    notifier.value = const MediaItemState(spoilerRevealed: true);
  }

  /// Hands out the origin [revealSpoiler] was given for [id] once, or null.
  Offset? takeRevealOrigin(MediaItemId id) {
    _assertAlive();
    return _revealOrigins.remove(id);
  }

  /// Hands out the send origin of [id] once, or null when there is none.
  ///
  /// Asks the host's lookup, which forgets the origin it returns.
  Rect? takeSendOrigin(MediaItemId id) {
    _assertAlive();
    return _sendOrigin?.call(id);
  }

  /// Where [id] is drawn now, in global coordinates, or null when no
  /// mounted view of this chat shows it (scrolled away, never shown).
  ///
  /// Asks the views that showed themselves through [attachOrigins], the
  /// latest first, so a row recycled and mounted again answers.
  Rect? rectOf(MediaItemId id) {
    _assertAlive();
    for (final lookup in _origins.reversed) {
      if (lookup(id) case final rect?) return rect;
    }
    return null;
  }

  /// Adds a mounted view's lookup to [rectOf]; [detachOrigins] removes it.
  @internal
  void attachOrigins(MediaOriginRect lookup) {
    if (_disposed || _origins.contains(lookup)) return;
    _origins.add(lookup);
  }

  /// Removes a lookup [attachOrigins] added.
  @internal
  void detachOrigins(MediaOriginRect lookup) => _origins.remove(lookup);

  /// Releases the item notifiers; the state is unusable afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final notifier in _items.values) {
      notifier.dispose();
    }
    _items.clear();
    _revealOrigins.clear();
    _origins.clear();
  }

  ValueNotifier<MediaItemState> _notifier(MediaItemId id) =>
      _items.putIfAbsent(id, () => ValueNotifier(const MediaItemState()));

  void _assertAlive() {
    assert(!_disposed, 'MessageMediaState was disposed.');
  }
}
