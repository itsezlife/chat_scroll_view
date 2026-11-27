import 'package:chat_capabilities/src/capability/capability.dart';
import 'package:chat_capabilities/src/diagnostics/capabilities_op.dart';
import 'package:chat_capabilities/src/feedback/capability_action.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// The package that reports an attempted denied action, named in the
/// `denied` diagnostics event.
///
/// Names and order are stable: logs filter by them. A new consumer is
/// declared last.
enum CapabilityConsumer {
  /// The composer: the input row, the locked field, a dimmed action, the
  /// send during slow mode.
  composer,

  /// The media picker.
  picker,

  /// The emoji, sticker and GIF panel.
  panel,

  /// Message and text selection (copy, forward, save).
  selection,

  /// The outbox: a server refusal of a sent message.
  outbox,
}

/// Where a package draws a denial text in place (a restriction bar, a
/// locked field, a picker page), named in the `denialTextMissing` event
/// when the host gives no text.
///
/// Each package keeps its own closed enum implementing this, as it does
/// its diagnostics operations, so this package knows no package's forms.
/// Only an enum can implement it; its `name` is what logs show, so names
/// are stable.
abstract interface class DenialForm implements Enum {}

/// The host's text for [action] denied for [reason], or null for the
/// package's silent form.
typedef CapabilityDenialText =
    String? Function(CapabilityAction action, DenialReason reason);

/// The host's report of an attempted [action], denied for [reason].
typedef CapabilityDeniedHandler =
    void Function(CapabilityAction action, DenialReason reason);

/// How the chat packages get the host's denial texts and report attempted
/// denied actions; the host passes one beside the capabilities listenable
/// to each controller and session.
///
/// The host gives the hooks; packages call [denialText] and [onDenied],
/// which guard them: a throwing hook is swallowed and reported as
/// `feedbackFailed`, so a host bug never breaks a send button or a picker.
/// Without hooks ([none]), texts are null and attempts go unreported, which
/// is the behaviour of a package before capabilities.
///
/// The value carries no UI: the host shows the tooltip, toast or bulletin.
@immutable
base class CapabilityFeedback {
  /// Feedback through the host's hooks; a missing hook is the silent form.
  const CapabilityFeedback({
    CapabilityDenialText? denialText,
    CapabilityDeniedHandler? onDenied,
  }) : _denialText = denialText,
       _onDenied = onDenied;

  /// No texts and no reports: what a package assumes without feedback.
  static const none = CapabilityFeedback();

  final CapabilityDenialText? _denialText;
  final CapabilityDeniedHandler? _onDenied;

  /// The text a package draws in place of a control of [action] denied for
  /// [reason] (a restriction bar, a picker page, a placeholder), or null for
  /// its silent form.
  ///
  /// A null text reports `denialTextMissing` (debug), with [form], the
  /// package's [DenialForm] for the silent form it then draws, so a host sees which
  /// texts it never gave. A throwing hook reports `feedbackFailed` instead
  /// and reads as null. [correlation] carries the chat id.
  @nonVirtual
  String? denialText(
    CapabilityAction action,
    DenialReason reason, {
    ChatCorrelation correlation = ChatCorrelation.none,
    DenialForm? form,
  }) {
    final String? text;
    try {
      text = _denialText?.call(action, reason);
    } on Object catch (error, stackTrace) {
      _reportFailure('denialText', action, error, stackTrace, correlation);
      return null;
    }
    if (text == null) {
      ChatDiagnostics.current.emit(
        ChatEventLevel.debug,
        ChatEventCategory.capabilities,
        CapabilitiesOp.denialTextMissing,
        correlation: correlation,
        fields: () => {
          'action': action,
          'reason': reason.diagnosticForm,
          'form': ?form,
        },
      );
    }
    return text;
  }

  /// Reports that the user attempted [action], denied for [reason]: a tap on
  /// a dimmed control, a send during slow mode, a server refusal.
  ///
  /// Every attempt reports `denied` (info) first, with or without a host
  /// hook ([none] too), so a log shows each attempt whatever the host does
  /// with it: the action, the reason form, the [consumer] that reported it
  /// and, given [remaining] (the slow mode wait of a `sendNow`), its
  /// milliseconds. The event lives here rather than in each consumer so
  /// every consumer reports the same fields.
  ///
  /// A [repeated] attempt (one inside the consumer's repeat window for the
  /// same action, while the host's feedback for the first is still up)
  /// reports `denied` with `repeated: true` and skips the hook, so the log
  /// keeps every attempt and the host's hints do not stack.
  ///
  /// The hook runs whatever the event does: diagnostics never stop the
  /// feedback. A throwing hook is swallowed and reports `feedbackFailed`.
  /// [correlation] carries the chat id and, when known, the message's.
  @nonVirtual
  void onDenied(
    CapabilityAction action,
    DenialReason reason, {
    required CapabilityConsumer consumer,
    Duration? remaining,
    bool repeated = false,
    ChatCorrelation correlation = ChatCorrelation.none,
  }) {
    try {
      ChatDiagnostics.current.emit(
        ChatEventLevel.info,
        ChatEventCategory.capabilities,
        CapabilitiesOp.denied,
        correlation: correlation,
        fields: () => {
          'action': action,
          'reason': reason.diagnosticForm,
          'consumer': consumer,
          'remainingMs': ?remaining?.inMilliseconds,
          if (repeated) 'repeated': true,
        },
      );
    } finally {
      if (!repeated) _callOnDenied(action, reason, correlation);
    }
  }

  void _callOnDenied(
    CapabilityAction action,
    DenialReason reason,
    ChatCorrelation correlation,
  ) {
    try {
      _onDenied?.call(action, reason);
    } on Object catch (error, stackTrace) {
      _reportFailure('onDenied', action, error, stackTrace, correlation);
    }
  }

  static void _reportFailure(
    String hook,
    CapabilityAction action,
    Object error,
    StackTrace stackTrace,
    ChatCorrelation correlation,
  ) => ChatDiagnostics.current.emit(
    ChatEventLevel.error,
    ChatEventCategory.capabilities,
    CapabilitiesOp.feedbackFailed,
    correlation: correlation,
    fields: () => {
      'hook': hook,
      'action': action,
      // A generic type's name can run longer than a field holds.
      'errorType': ChatEvent.clip(error.runtimeType.toString()),
    },
    error: error,
    stackTrace: stackTrace,
  );
}
