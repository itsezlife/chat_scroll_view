import 'package:chat_capabilities/src/flags/media_kind.dart';

/// An action a chat's capabilities may deny, as the host's denial feedback
/// sees it: the subject of `CapabilityFeedback.denialText` and
/// `CapabilityFeedback.onDenied`.
///
/// Names and order are stable: a host may persist them or switch on them, so
/// a new action is declared last. Blocking screen capture is a protection
/// flag, not an action: nobody attempts it.
enum CapabilityAction {
  /// Sending a text message.
  sendText,

  /// Sending a photo.
  sendPhoto,

  /// Sending a video.
  sendVideo,

  /// Sending an animation (a GIF or another silent looping clip).
  sendAnimation,

  /// Sending a file as a document.
  sendFile,

  /// Sending an audio file.
  sendAudio,

  /// Sending a voice message.
  sendVoice,

  /// Sending a round video message.
  sendRoundVideo,

  /// Sending a sticker.
  sendSticker,

  /// Sending a message with a link preview.
  sendLinkPreview,

  /// Sending a poll.
  sendPoll,

  /// Sending an inline result.
  sendInline,

  /// Sending now, before slow mode's interval has passed.
  sendNow,

  /// Copying a message's content.
  copy,

  /// Forwarding a message.
  forward,

  /// Saving a message's media.
  save;

  /// The action of sending media of [kind].
  static CapabilityAction forMediaKind(MediaKind kind) => switch (kind) {
    MediaKind.photo => sendPhoto,
    MediaKind.video => sendVideo,
    MediaKind.animation => sendAnimation,
    MediaKind.file => sendFile,
    MediaKind.audio => sendAudio,
    MediaKind.voice => sendVoice,
    MediaKind.roundVideo => sendRoundVideo,
  };
}
