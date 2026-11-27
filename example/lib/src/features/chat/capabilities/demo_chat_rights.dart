import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_kind.dart';

/// The demo's stand-in for what a backend says the user may do in a chat:
/// the host side of the chat capabilities, resolved to a
/// [ChatCapabilities] value by [resolve].
///
/// A real host resolves its rights (creator, admin, a personal ban with its
/// date, the default ban, a boost) into outcomes; the demo names four
/// chats' worth of outcomes instead, so each denied form has a chat that
/// shows it.
enum DemoChatRights {
  /// A member who may do everything, within the demo backend's limits.
  member,

  /// A channel the user reads but does not post in: the input row is the
  /// read-only bar.
  readOnly,

  /// A group whose admins banned some of what the user sends: photos and
  /// videos until a date, files and GIFs for everyone, voice for good, and
  /// stickers until the chat is boosted.
  banned,

  /// A group in slow mode: one send every 30 seconds.
  slowMode;

  /// The rights of a chat of [kind] that names none: a channel is read
  /// only, the others let a member do everything.
  static DemoChatRights forKind(ChatKind kind) => switch (kind) {
    ChatKind.channel => readOnly,
    ChatKind.privateChat || ChatKind.group => member,
  };

  /// The slow mode interval of a [slowMode] chat (and of the debug
  /// switcher's slow mode).
  static const Duration slowModeInterval = Duration(seconds: 30);

  /// The longest file the demo backend takes: 2000 MB.
  static const int fileSizeLimit = 2000 * 1024 * 1024;

  /// The demo backend's limits, the same in every chat: the message length
  /// it is configured with ([DemoConfig.messageLengthMax]) and files up to
  /// [fileSizeLimit]; captions and albums keep the defaults.
  static const ChatLimits limits = ChatLimits(
    messageLength: DemoConfig.messageLengthMax,
    fileSize: fileSizeLimit,
  );

  /// The opaque kind of what lifts a [banned] chat's sticker ban: the
  /// chat's boosts.
  static const String boostUnlock = 'boost';

  /// The capabilities of a chat with these rights, resolved at [now] (a
  /// dated ban ends a day after it).
  ChatCapabilities resolve(DateTime now) => switch (this) {
    member => const ChatCapabilities(limits: limits),
    readOnly => const ChatCapabilities(
      writeAccess: WriteAccess.readOnly(),
      limits: limits,
    ),
    banned => ChatCapabilities(
      sending: SendingCapabilities(
        media: SendableMedia(
          allowed: MediaKindSet.all.without(_bannedKinds),
          denials: {
            MediaKind.photo: DenialReason.restricted(
              until: now.add(const Duration(days: 1)),
            ),
            MediaKind.video: DenialReason.restricted(
              until: now.add(const Duration(days: 1)),
            ),
            MediaKind.file: const DenialReason.everyone(),
            MediaKind.animation: const DenialReason.everyone(),
            MediaKind.voice: const DenialReason.restricted(),
          },
        ),
        stickers: const Capability.denied(DenialReason.unlockable(boostUnlock)),
      ),
      limits: limits,
    ),
    slowMode => const ChatCapabilities(
      slowMode: SlowMode(interval: slowModeInterval),
      limits: limits,
    ),
  };

  static final MediaKindSet _bannedKinds = MediaKindSet.of({
    MediaKind.photo,
    MediaKind.video,
    MediaKind.file,
    MediaKind.animation,
    MediaKind.voice,
  });
}
