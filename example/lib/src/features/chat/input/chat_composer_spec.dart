import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';

/// The ids of the composer's actions, so a test and a golden name the same
/// ones.
abstract final class ChatComposerActions {
  /// The panel's toggle: the page's icon, or the keyboard's while the panel
  /// is up.
  static const String panel = 'panel';

  /// Attach.
  static const String attach = 'attach';

  /// The one action of the end slot: voice for an empty composer, send for
  /// text, confirm for an edit.
  static const String primary = 'primary';
}

/// Builds the composer's description of the moment from the chat's state.
///
/// Rebuilt by the host whenever the text, the edit, the busy flag or the
/// panel changes; the composer view holds no mode of its own.
ComposerSpec buildChatComposerSpec({
  required ChromeStrings strings,
  required ChatEditTarget? editing,
  required bool hasText,
  required bool busy,
  required bool panelOpen,
  required ChromeIconId pageIcon,
  required VoidCallback onTogglePanel,
  required VoidCallback onSubmit,
  required VoidCallback onAttach,
  required VoidCallback onVoice,
  required VoidCallback onCancelEdit,
}) {
  final composer = strings.composer;
  final isEditing = editing != null;
  return ComposerSpec(
    header: isEditing
        ? ComposerHeader.edit(preview: editing.preview, onDismiss: onCancelEdit)
        : null,
    busy: busy,
    actions: [
      ActionDescriptor(
        id: ChatComposerActions.panel,
        icon: panelOpen ? ChromeIconId.keyboard : pageIcon,
        semanticLabel: panelOpen
            ? composer.showKeyboardAction
            : composer.showPanelAction,
        placement: ActionPlacement.leading,
        onTap: onTogglePanel,
      ),
      ActionDescriptor(
        id: ChatComposerActions.attach,
        icon: ChromeIconId.attach,
        semanticLabel: composer.attachAction,
        visible: !isEditing,
        onTap: onAttach,
      ),
      ActionDescriptor(
        id: ChatComposerActions.primary,
        icon: switch ((isEditing, hasText)) {
          (true, _) => ChromeIconId.confirm,
          (false, true) => ChromeIconId.send,
          (false, false) => ChromeIconId.voice,
        },
        semanticLabel: switch ((isEditing, hasText)) {
          (true, _) => composer.confirmEditAction,
          (false, true) => composer.sendAction,
          (false, false) => composer.recordVoiceAction,
        },
        primary: hasText,
        onTap: hasText ? onSubmit : onVoice,
      ),
    ],
  );
}
