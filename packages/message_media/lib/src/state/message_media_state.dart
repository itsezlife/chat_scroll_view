import 'dart:ui' show Offset, Rect;

import 'package:chrome_foundation/chrome_foundation.dart'
    show ChromeInputClass, ChromeWidthClass;
import 'package:content_model/content_model.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:listen/listen.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:meta/meta.dart';

/// A rect of one media item in global coordinates, or null where there is
/// none: the one-shot send origin an outgoing item was picked from (null
/// when there is none or it was already handed out), or a mounted view's
/// answer to where one of its items is drawn (null for one it does not
/// show).
///
/// Declared here so that the host wires its outbox's `takeSendOrigin` in one
/// line and neither package depends on the other.
typedef MediaItemRect = Rect? Function(MediaItemId id);

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
  MessageMediaState({MediaItemRect? sendOrigin}) : _sendOrigin = sendOrigin;

  final MediaItemRect? _sendOrigin;
  final Map<MediaItemId, ValueNotifier<MediaItemState>> _items = {};
  final Map<MediaItemId, Offset> _revealOrigins = {};
  final List<MediaItemRect> _origins = [];
  bool _disposed = false;
  ({ChromeWidthClass width, ChromeInputClass input})? _$webClasses;

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
  void attachOrigins(MediaItemRect lookup) {
    if (_disposed || _origins.contains(lookup)) return;
    _origins.add(lookup);
  }

  /// Removes a lookup [attachOrigins] added.
  @internal
  void detachOrigins(MediaItemRect lookup) => _origins.remove(lookup);

  /// Notes the window's width class and the input class a web view of this
  /// chat was built under, and reports a change from the last ones noted
  /// (`media` / `webClassChanged`, with [chatId]) after the frame.
  ///
  /// Every view of the chat notes them on each build, and a resize rebuilds
  /// them all, so the state keeps what it last saw: one report per change,
  /// not one per view or per frame. The first note reports nothing, there
  /// being nothing it changed from. The report waits for the frame's end:
  /// a build reports nothing of its own.
  @internal
  void noteWebClasses(
    ChromeWidthClass width,
    ChromeInputClass input, {
    String? chatId,
  }) {
    if (_disposed) return;
    final last = _$webClasses;
    _$webClasses = (width: width, input: input);
    if (last == null || (last.width == width && last.input == input)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      ChatDiagnostics.current.emit(
        ChatEventLevel.debug,
        ChatEventCategory.media,
        MediaOp.webClassChanged,
        correlation: ChatCorrelation(chatId: chatId),
        fields: () => {
          'from': last.width.name,
          'to': width.name,
          'input': input.name,
        },
      );
    });
  }

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
