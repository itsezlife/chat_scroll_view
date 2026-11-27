import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_capabilities_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/demo_chat_rights.dart';

/// One on / off row of the debug switcher: a right (on is allowed), the
/// slow mode, a protection flag (on is protected) or the tight limits.
///
/// Each row reads its state from a value ([isOn]) and flips it ([flip]), so
/// the sheet is a list of rows and the switcher one guard over them.
enum CapabilityToggle {
  /// `sending.text`.
  text('Text'),

  /// `sending.media`, photos.
  photo('Photos'),

  /// `sending.media`, videos.
  video('Videos'),

  /// `sending.media`, GIFs.
  animation('GIFs'),

  /// `sending.media`, files.
  file('Files'),

  /// `sending.media`, music.
  audio('Music'),

  /// `sending.media`, voice messages.
  voice('Voice messages'),

  /// `sending.media`, video messages.
  roundVideo('Video messages'),

  /// `sending.stickers`.
  stickers('Stickers'),

  /// `sending.linkPreviews`.
  linkPreviews('Link previews'),

  /// Slow mode, 30 s between sends; turned on with a wait already running.
  slowMode('Slow mode (30 s)'),

  /// Slow mode's `pending`: a message of the user's is still sending.
  slowModePending('Slow mode: a send pending'),

  /// `protection.copy` denied.
  copyProtected('Copy protected'),

  /// `protection.forward` denied.
  forwardProtected('Forward protected'),

  /// `protection.save` denied.
  saveProtected('Save protected'),

  /// `protection.captureBlocked`.
  captureBlocked('Screen capture blocked'),

  /// The [tight] limits in place of the demo backend's.
  tightLimits('Tight limits (200 / 50 / 10 MB / 3)');

  const CapabilityToggle(this.label);

  /// The row's label.
  final String label;

  /// The media kind a media row stands for; null for the other rows.
  MediaKind? get _mediaKind => switch (this) {
    photo => MediaKind.photo,
    video => MediaKind.video,
    animation => MediaKind.animation,
    file => MediaKind.file,
    audio => MediaKind.audio,
    voice => MediaKind.voice,
    roundVideo => MediaKind.roundVideo,
    _ => null,
  };

  /// The limits of the tight row: a message of 200 code points, captions
  /// of 50, files to 10 MB, albums of 3.
  static const ChatLimits tight = ChatLimits(
    messageLength: 200,
    captionLength: 50,
    fileSize: 10 * 1024 * 1024,
    albumSize: 3,
  );

  /// What a right turned off is denied with.
  static const DenialReason deniedReason = DenialReason.restricted();

  /// Whether the row is on in [value].
  bool isOn(ChatCapabilities value) {
    if (_mediaKind case final kind?) {
      return value.sending.media.allowed.contains(kind);
    }
    final sending = value.sending;
    final protection = value.protection;
    return switch (this) {
      text => sending.text.isAllowed,
      stickers => sending.stickers.isAllowed,
      linkPreviews => sending.linkPreviews.isAllowed,
      slowMode => value.slowMode.isActive,
      slowModePending => value.slowMode.pending,
      copyProtected => !protection.copy,
      forwardProtected => !protection.forward,
      saveProtected => !protection.save,
      captureBlocked => protection.captureBlocked,
      tightLimits => value.limits == tight,
      // The media rows returned above.
      _ => throw StateError('$this is a media row'),
    };
  }

  /// Whether the row can be flipped in [value]: `pending` only in slow mode.
  bool enabledIn(ChatCapabilities value) =>
      this != slowModePending || value.slowMode.isActive;

  /// [value] with this row flipped, at [now] (a slow mode turned on waits an
  /// interval from it).
  ChatCapabilities flip(ChatCapabilities value, DateTime now) {
    final on = !isOn(value);
    if (_mediaKind case final kind?) {
      final media = value.sending.media;
      final only = MediaKindSet.of({kind});
      return value.copyWith(
        sending: value.sending.copyWith(
          media: SendableMedia(
            allowed: on ? media.allowed | only : media.allowed.without(only),
            denials: {
              for (final MapEntry(:key, value: reason) in media.denials.entries)
                if (key != kind) key: reason,
              if (!on) kind: deniedReason,
            },
          ),
        ),
      );
    }
    Capability right() =>
        on ? const Capability.allowed() : const Capability.denied(deniedReason);
    final sending = value.sending;
    final protection = value.protection;
    return switch (this) {
      text => value.copyWith(sending: sending.copyWith(text: right())),
      stickers => value.copyWith(sending: sending.copyWith(stickers: right())),
      linkPreviews => value.copyWith(
        sending: sending.copyWith(linkPreviews: right()),
      ),
      slowMode => value.copyWith(
        slowMode: on
            ? SlowMode(
                interval: DemoChatRights.slowModeInterval,
                nextSendAt: now.add(DemoChatRights.slowModeInterval),
              )
            : SlowMode.none,
      ),
      slowModePending => value.copyWith(
        slowMode: value.slowMode.copyWith(pending: on),
      ),
      copyProtected => value.copyWith(
        protection: protection.copyWith(copy: !on),
      ),
      forwardProtected => value.copyWith(
        protection: protection.copyWith(forward: !on),
      ),
      saveProtected => value.copyWith(
        protection: protection.copyWith(save: !on),
      ),
      captureBlocked => value.copyWith(
        protection: protection.copyWith(captureBlocked: on),
      ),
      tightLimits => value.copyWith(limits: on ? tight : DemoChatRights.limits),
      // The media rows returned above.
      _ => throw StateError('$this is a media row'),
    };
  }
}

/// The write access the debug switcher can choose: the input row itself,
/// or each of its replacements.
enum WriteAccessChoice {
  /// The field.
  canWrite('Can write', WriteAccess.canWrite()),

  /// The read-only bar.
  readOnly('Read only', WriteAccess.readOnly()),

  /// The join bar.
  join('Join', WriteAccess.join()),

  /// The request-to-join bar.
  requestToJoin('Request to join', WriteAccess.requestToJoin()),

  /// The ban bar, for good.
  restricted('Banned', WriteAccess.restricted(DenialReason.restricted())),

  /// The ban bar with the lift action: the chat's boost lifts it.
  unlockable(
    'Banned, boost lifts',
    WriteAccess.restricted(DenialReason.unlockable(DemoChatRights.boostUnlock)),
  ),

  /// A replacement the host draws, by tag.
  custom('Custom (premium)', WriteAccess.custom('premiumRequired'));

  const WriteAccessChoice(this.label, this.access);

  /// The choice's label.
  final String label;

  /// The write access it sets.
  final WriteAccess access;

  /// The choice that sets [access], or null for one the switcher does not
  /// offer.
  static WriteAccessChoice? of(WriteAccess access) {
    for (final choice in values) {
      if (choice.access == access) return choice;
    }
    return null;
  }
}

/// The debug switcher's behaviour: flips one row of a chat's capabilities
/// live, through its [host], so the composer and the picker react as they
/// would to the backend.
///
/// Each row is guarded: a flip within [guard] of the row's last one is
/// ignored, so a burst of taps (or a double tap read as two) flips once.
final class CapabilitiesSwitcher {
  /// The switcher over [host]'s value.
  CapabilitiesSwitcher(
    this.host, {
    this.guard = defaultGuard,
    DateTime Function() now = DateTime.now,
  }) : _now = now;

  /// How long after a row's flip a second flip of it is ignored.
  static const defaultGuard = Duration(milliseconds: 400);

  /// The chat whose capabilities the rows change.
  final ChatCapabilitiesHost host;

  /// The repeat window of each row.
  final Duration guard;

  final DateTime Function() _now;
  final Map<Object, DateTime> _lastFlip = {};

  /// Flips [row]; false when its guard ignored it or the row is disabled.
  bool toggle(CapabilityToggle row) {
    if (!row.enabledIn(host.value) || !_pass(row)) return false;
    host.set(row.flip(host.value, _now()));
    return true;
  }

  /// Sets the write access of [choice]; false when the guard ignored it.
  bool choose(WriteAccessChoice choice) {
    if (!_pass(WriteAccessChoice)) return false;
    host.update((c) => c.copyWith(writeAccess: choice.access));
    return true;
  }

  bool _pass(Object row) {
    final now = _now();
    if (_lastFlip[row] case final last? when now.difference(last) < guard) {
      return false;
    }
    _lastFlip[row] = now;
    return true;
  }
}
