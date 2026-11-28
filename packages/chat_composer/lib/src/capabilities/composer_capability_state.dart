import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_composer/src/spec/composer_panel.dart';
import 'package:meta/meta.dart';

/// What the chat's capabilities make of the composer's row at one moment:
/// the panel that replaces it, the locked field, the denied actions and the
/// chat's message budget, with the host's texts for them already asked.
///
/// `ComposerController.capabilities` holds it while a view binds the
/// chat's capabilities; [unbound] otherwise, which changes nothing. A view
/// draws from it and asks no rule of its own.
@immutable
final class ComposerCapabilityState {
  /// The state of bound capabilities.
  const ComposerCapabilityState({
    required this.writeAccess,
    required this.sending,
    required this.messageLength,
    required this.slowModeActive,
    this.accessText,
    this.lockedHint,
  }) : isBound = true;

  const ComposerCapabilityState._unbound()
    : isBound = false,
      writeAccess = const WriteAccess.canWrite(),
      sending = const SendingCapabilities(),
      messageLength = null,
      slowModeActive = false,
      accessText = null,
      lockedHint = null;

  /// No capabilities: the composer is what it was before them.
  static const unbound = ComposerCapabilityState._unbound();

  /// Whether a view bound the chat's capabilities.
  final bool isBound;

  /// The chat's write access.
  final WriteAccess writeAccess;

  /// The chat's sending rights.
  final SendingCapabilities sending;

  /// The chat's message length budget; null when unbound.
  final int? messageLength;

  /// Whether a slow mode applies (its countdown is
  /// `ComposerController.slowMode`).
  final bool slowModeActive;

  /// The host's text for the panel that replaces the row; null for its
  /// silent form or when the user may write.
  final String? accessText;

  /// The host's placeholder for the locked field; null for its silent form
  /// or when text is allowed.
  final String? lockedHint;

  /// The default panel that replaces the row, or null when the user may
  /// write (and when unbound).
  ComposerPanelId? get accessPanel => switch (isBound) {
    true => ComposerPanelId.forWriteAccess(writeAccess),
    false => null,
  };

  /// Whether the row offers the spec's actions: not while [accessPanel]
  /// replaces it. The panel takes the whole row, send included, so a draft
  /// the field held is kept (the controller's text is untouched and comes
  /// back with the field) but cannot be sent until the user may write.
  bool get offersActions => accessPanel == null;

  /// Why plain text is denied, locking the field; null when it is allowed.
  DenialReason? get textDenial => denialOf(CapabilityAction.sendText);

  /// Why an action of [action] is denied; null when allowed or unbound.
  DenialReason? denialOf(CapabilityAction action) => switch (isBound) {
    true => sending.reasonFor(action),
    false => null,
  };

  @override
  bool operator ==(Object other) =>
      other is ComposerCapabilityState &&
      other.isBound == isBound &&
      other.writeAccess == writeAccess &&
      other.sending == sending &&
      other.messageLength == messageLength &&
      other.slowModeActive == slowModeActive &&
      other.accessText == accessText &&
      other.lockedHint == lockedHint;

  @override
  int get hashCode => Object.hash(
    isBound,
    writeAccess,
    sending,
    messageLength,
    slowModeActive,
    accessText,
    lockedHint,
  );

  @override
  String toString() => switch (isBound) {
    false => 'ComposerCapabilityState.unbound',
    true =>
      'ComposerCapabilityState(writeAccess: $writeAccess, '
          'sending: $sending, messageLength: $messageLength, '
          'slowModeActive: $slowModeActive)',
  };
}
