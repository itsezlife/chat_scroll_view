import 'package:chat_capabilities/chat_capabilities.dart';

/// Why [sending] denies [action], or null when it allows it or the action
/// is not a sending right the composer reads.
///
/// `sendNow` is slow mode's and `copy`, `forward` and `save` are
/// protection's: none of them is a composer action's capability here.
DenialReason? sendingDenial(
  SendingCapabilities sending,
  CapabilityAction action,
) => switch (action) {
  CapabilityAction.sendText => _reason(sending.text),
  CapabilityAction.sendPhoto => sending.media.reasonFor(MediaKind.photo),
  CapabilityAction.sendVideo => sending.media.reasonFor(MediaKind.video),
  CapabilityAction.sendAnimation => sending.media.reasonFor(
    MediaKind.animation,
  ),
  CapabilityAction.sendFile => sending.media.reasonFor(MediaKind.file),
  CapabilityAction.sendAudio => sending.media.reasonFor(MediaKind.audio),
  CapabilityAction.sendVoice => sending.media.reasonFor(MediaKind.voice),
  CapabilityAction.sendRoundVideo => sending.media.reasonFor(
    MediaKind.roundVideo,
  ),
  CapabilityAction.sendSticker => _reason(sending.stickers),
  CapabilityAction.sendLinkPreview => _reason(sending.linkPreviews),
  CapabilityAction.sendPoll => _reason(sending.polls),
  CapabilityAction.sendInline => _reason(sending.inline),
  CapabilityAction.sendNow ||
  CapabilityAction.copy ||
  CapabilityAction.forward ||
  CapabilityAction.save => null,
};

DenialReason? _reason(Capability capability) => switch (capability) {
  Capability$Allowed() => null,
  Capability$Denied(:final reason) => reason,
};

/// The reason a default write-access panel's text is asked for with: a
/// restriction's own, otherwise `other` with the form's name or the host's
/// tag; null when the user may write.
DenialReason? writeAccessReason(WriteAccess access) => switch (access) {
  WriteAccess$CanWrite() => null,
  WriteAccess$ReadOnly() => const DenialReason.other('readOnly'),
  WriteAccess$Join() => const DenialReason.other('join'),
  WriteAccess$RequestToJoin() => const DenialReason.other('requestToJoin'),
  WriteAccess$Restricted(:final reason) => reason,
  WriteAccess$Custom(:final tag) => DenialReason.other(tag),
};
