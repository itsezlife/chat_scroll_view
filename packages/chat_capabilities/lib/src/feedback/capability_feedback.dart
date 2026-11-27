import 'package:chat_capabilities/src/capability/capability.dart';
import 'package:chat_capabilities/src/diagnostics/capabilities_op.dart';
import 'package:chat_capabilities/src/feedback/capability_action.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

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
  /// package's name for the silent form it then draws, so a host sees which
  /// texts it never gave. A throwing hook reports `feedbackFailed` instead
  /// and reads as null. [correlation] carries the chat id.
  @nonVirtual
  String? denialText(
    CapabilityAction action,
    DenialReason reason, {
    ChatCorrelation correlation = ChatCorrelation.none,
    String? form,
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
  /// A throwing hook is swallowed and reports `feedbackFailed`.
  /// [correlation] carries the chat id and, when known, the message's.
  @nonVirtual
  void onDenied(
    CapabilityAction action,
    DenialReason reason, {
    ChatCorrelation correlation = ChatCorrelation.none,
  }) {
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
      'errorType': _clip(error.runtimeType.toString()),
    },
    error: error,
    stackTrace: stackTrace,
  );

  // A field string holds at most 64 characters; a generic type's name can
  // run longer.
  static String _clip(String name) =>
      name.length <= 64 ? name : name.substring(0, 64);
}
