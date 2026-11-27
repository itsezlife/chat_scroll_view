import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:flutter/widgets.dart';

/// Names which panel occupies the input row: the text field, a recording
/// surface, a recorded-message preview, a "join" or "restricted" bar.
///
/// An open set, like [ComposerQueryKind]: the host names any panel of its
/// own here and builds it in the [ComposerPanelResolver].
///
/// The composer builds two kinds itself:
///
/// - [text], the entity-aware text field;
/// - the **default panels** of the chat's write access, which the composer
///   puts in the row in place of the requested panel when the controller's
///   capabilities say the user may not write ([forWriteAccess]): [readOnly],
///   [join], [requestToJoin], [restricted] and [writeAccessCustom]. Each is a
///   plain text node with the host's denial text (`CapabilityFeedback`,
///   asked for `CapabilityAction.sendText` with the reason named on each id)
///   and, below it, an optional host action (`ComposerView.accessAction`).
///
/// The resolver is asked first for every id but [text]; a default panel is
/// built only when it returns null, so a host replaces any default panel by
/// building its id.
extension type const ComposerPanelId(String value) {
  /// The default panel: the entity-aware text field.
  static const ComposerPanelId text = ComposerPanelId('text');

  /// The user reads only (a broadcast): typically a mute / unmute bar, the
  /// host's verb as the action. Its text is asked for with
  /// `DenialReason.other('readOnly')`.
  static const ComposerPanelId readOnly = ComposerPanelId('readOnly');

  /// The user must join to write: the host's join verb as the action. Its
  /// text is asked for with `DenialReason.other('join')`.
  static const ComposerPanelId join = ComposerPanelId('join');

  /// The user must ask to join: the host's request verb as the action. Its
  /// text is asked for with `DenialReason.other('requestToJoin')`.
  static const ComposerPanelId requestToJoin = ComposerPanelId('requestToJoin');

  /// Writing is denied: the restriction bar, with the ban text for the
  /// write access's own reason and, for an `unlockable` reason, the host's
  /// action that lifts it.
  static const ComposerPanelId restricted = ComposerPanelId('restricted');

  /// A host form of write access (`WriteAccess.custom(tag)`): premium
  /// required, a closed topic. Its text is asked for with
  /// `DenialReason.other(tag)`; a host with several such forms builds this
  /// id itself from its own capabilities.
  static const ComposerPanelId writeAccessCustom = ComposerPanelId(
    'writeAccessCustom',
  );

  /// The default panel that replaces the input row for [access], or null
  /// when the user may write (the requested panel stays).
  static ComposerPanelId? forWriteAccess(WriteAccess access) =>
      switch (access) {
        WriteAccess$CanWrite() => null,
        WriteAccess$ReadOnly() => readOnly,
        WriteAccess$Join() => join,
        WriteAccess$RequestToJoin() => requestToJoin,
        WriteAccess$Restricted() => restricted,
        WriteAccess$Custom() => writeAccessCustom,
      };
}

/// Builds the widget for a panel other than [ComposerPanelId.text].
///
/// Returns null for an id the host does not build. For a default panel of
/// the write access the composer then builds its own; for any other id it
/// asserts in debug builds and shows an empty row. The widget fills the row
/// between the actions and may be any height at or above the island height:
/// the island animates to it.
typedef ComposerPanelResolver =
    Widget? Function(BuildContext context, ComposerPanelId panel);

/// The host's action on a default write-access panel: the verb of a
/// read-only, join or request-to-join bar, or what lifts an `unlockable`
/// restriction.
@immutable
final class ComposerPanelAction {
  /// An action labelled [label] that calls [onTap].
  const ComposerPanelAction({required this.label, required this.onTap})
    : assert(label != '', 'a panel action needs a label');

  /// What the action reads, and what assistive technology announces.
  final String label;

  /// Called on tap or activation. The host guards it against a repeat (a
  /// join already in flight), since only it knows when the action is done.
  final VoidCallback onTap;
}

/// The host's action for the default panel of [access], or null for a
/// panel of text alone.
typedef ComposerPanelActionResolver =
    ComposerPanelAction? Function(WriteAccess access);
