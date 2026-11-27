import 'package:chat_capabilities/src/capability/capability.dart';
import 'package:chat_capabilities/src/feedback/capability_action.dart';
import 'package:chat_capabilities/src/feedback/capability_feedback.dart';

/// One attempted denied action that reached the host.
typedef RecordedDenial = ({CapabilityAction action, DenialReason reason});

/// Denial feedback for tests of consumers: it records every attempt and
/// answers texts from a table.
///
/// The hooks sit behind the real seam, so a consumer under test also emits
/// the seam's diagnostics events (`denialTextMissing` for an action with no
/// text in [texts]).
final class RecordingCapabilityFeedback extends CapabilityFeedback {
  /// Feedback answering [texts] by action, recording no attempt yet.
  RecordingCapabilityFeedback({Map<CapabilityAction, String> texts = const {}})
    : this._(<RecordedDenial>[], Map.of(texts));

  RecordingCapabilityFeedback._(List<RecordedDenial> denials, this.texts)
    : _denials = denials,
      super(
        denialText: (action, _) => texts[action],
        onDenied: (action, reason) =>
            denials.add((action: action, reason: reason)),
      );

  /// The text for each action, whatever the reason; a test may change it.
  final Map<CapabilityAction, String> texts;

  final List<RecordedDenial> _denials;

  /// Every attempt reported through `onDenied`, oldest first.
  List<RecordedDenial> get denials => List.unmodifiable(_denials);
}
