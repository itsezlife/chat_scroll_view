import 'package:catalog_assets/catalog_assets.dart' show AssetRestFrame;
import 'package:content_model/content_model.dart'
    show ContentKey, ContentKey$Unicode;

/// How the sticker of an emoji-only body plays: the host's policy, never the
/// body's.
///
/// The reference clients agree on the kinds and differ on the details, so the
/// host picks from the asset kind and the user's animation settings; the body
/// reads no setting.
///
/// | Mode | Reference behaviour |
/// | --- | --- |
/// | [loop] | a custom emoji and an ordinary animated sticker, while the user's autoplay setting allows it |
/// | [onceThenFirstFrame] | the single unicode emoji on Android and Desktop |
/// | [onceThenLastFrame] | the single unicode emoji on iOS (its player is not in the checked source: unverified) |
/// | [still] | any of them with autoplay off (power saving) |
///
/// A sticker that is not looping plays once, the first time the open chat
/// shows it ([ChatStickerPlayLedger]), rests on its rest frame, and plays one
/// more pass on each replay: a tap, a long press under the mobile tap policy,
/// or an interaction from the peer.
enum ChatStickerPlayback {
  /// Plays and loops whenever it is shown; remembers nothing.
  loop,

  /// Plays once on the first show, then rests on the first frame.
  onceThenFirstFrame,

  /// Plays once on the first show, then rests on the last frame.
  onceThenLastFrame,

  /// Rests on the first frame and plays only when replayed.
  still;

  /// The reference client's mode for the single emoji [emoji]: a unicode emoji
  /// plays once and rests on the first frame (Android and Desktop), a custom
  /// emoji loops.
  static ChatStickerPlayback defaultFor(ContentKey emoji) => switch (emoji) {
    ContentKey$Unicode() => onceThenFirstFrame,
    _ => loop,
  };

  /// Whether the sticker loops.
  bool get loops => this == loop;

  /// Whether the first show of the message in the open chat plays it, which
  /// the [ChatStickerPlayLedger] decides and records.
  bool get playsOnFirstShow =>
      this == onceThenFirstFrame || this == onceThenLastFrame;

  /// The frame a pass rests on.
  AssetRestFrame get restFrame =>
      this == onceThenLastFrame ? AssetRestFrame.last : AssetRestFrame.first;
}

/// The host's memory of which stickers already played in the open chat.
///
/// Per message id and per open chat: a new chat controller starts empty, so a
/// reopened chat plays them again, as the reference clients do (Android keeps
/// a map on the chat screen, iOS a set on the chat's interaction object,
/// Desktop a set on the chat widget). The body keeps none of it, so it
/// survives a row being recycled and mounted again; it is not persisted.
///
/// The body asks [hasPlayed] when a body mounts and keeps the answer for that
/// mount, then calls [markPlayed] once the animation is playing (the
/// reference marks at the first drawn frame, not at the end, so a sticker the
/// user scrolled past after one frame does not play again). Both are called
/// while the body builds or paints: record, do not rebuild.
abstract interface class ChatStickerPlayLedger {
  /// Whether the sticker of [messageId] already played in this chat.
  bool hasPlayed(int messageId);

  /// Records that the sticker of [messageId] played.
  void markPlayed(int messageId);
}
