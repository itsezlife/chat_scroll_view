import 'package:attach_model/attach_model.dart';
import 'package:flutter/foundation.dart';

/// Why the camera took no video.
enum AttachVideoRefusal {
  /// Only photos may be sent here: a hold asked for a video.
  notAllowed,

  /// The microphone a video needs was refused.
  microphone,
}

/// An **attach interaction**: something the sheet did that the host may give
/// feedback for (a bulletin, a sound). The sheet draws its own motion (a
/// shake) and plays the policy's haptic; words are the host's.
@immutable
sealed class AttachInteraction {
  const AttachInteraction._();

  /// A send was refused: the caption is [over] code points past the limit.
  const factory AttachInteraction.captionTooLong({required int over}) =
      AttachInteraction$CaptionTooLong;

  /// An item could not join the selection, for [reason].
  const factory AttachInteraction.refused(AttachRefusal reason) =
      AttachInteraction$Refused;

  /// The camera took no video, for [reason].
  const factory AttachInteraction.videoRefused(AttachVideoRefusal reason) =
      AttachInteraction$VideoRefused;
}

/// [AttachInteraction.videoRefused].
final class AttachInteraction$VideoRefused extends AttachInteraction {
  /// A video refused for [reason].
  const AttachInteraction$VideoRefused(this.reason) : super._();

  /// Why.
  final AttachVideoRefusal reason;

  @override
  bool operator ==(Object other) =>
      other is AttachInteraction$VideoRefused && other.reason == reason;

  @override
  int get hashCode => Object.hash(AttachInteraction$VideoRefused, reason);

  @override
  String toString() => 'AttachInteraction.videoRefused(${reason.name})';
}

/// [AttachInteraction.captionTooLong].
final class AttachInteraction$CaptionTooLong extends AttachInteraction {
  /// A caption [over] the limit.
  const AttachInteraction$CaptionTooLong({required this.over}) : super._();

  /// How many code points past the limit.
  final int over;

  @override
  bool operator ==(Object other) =>
      other is AttachInteraction$CaptionTooLong && other.over == over;

  @override
  int get hashCode => Object.hash(AttachInteraction$CaptionTooLong, over);

  @override
  String toString() => 'AttachInteraction.captionTooLong(over: $over)';
}

/// [AttachInteraction.refused].
final class AttachInteraction$Refused extends AttachInteraction {
  /// A refusal for [reason].
  const AttachInteraction$Refused(this.reason) : super._();

  /// Why.
  final AttachRefusal reason;

  @override
  bool operator ==(Object other) =>
      other is AttachInteraction$Refused && other.reason == reason;

  @override
  int get hashCode => Object.hash(AttachInteraction$Refused, reason);

  @override
  String toString() => 'AttachInteraction.refused(${reason.name})';
}
