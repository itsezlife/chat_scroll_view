import 'package:chat_capabilities/chat_capabilities.dart' show CapabilityAction;
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';

/// The ids of the composer's actions, so a test and a golden name the same
/// ones.
abstract final class ChatComposerActions {
  /// The panel's toggle: the page's icon in every state, or the keyboard's
  /// while a panel that replaces the keyboard is up.
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
///
/// The panel's toggle sits where the platform's panel is reached from: first
/// at the start edge where the panel replaces the keyboard, and at the end
/// edge, under the popup that anchors to it, where the panel is a popup or a
/// dock ([panelPlacement]). Attach takes the other edge.
///
/// [deniedForms] are the composer's (the platform's by default): where they
/// dim the emoji toggle with a locked field, the toggle carries the text
/// right.
ComposerSpec buildChatComposerSpec({
  required ChromeStrings strings,
  required ChatEditTarget? editing,
  required bool hasText,
  required bool busy,
  required int? messageLengthLimit,
  required bool panelReplacesKeyboard,
  required bool panelDocked,
  required ActionPlacement panelPlacement,
  required ActionWrap? wrapPanelToggle,
  required ChromeIconId pageIcon,
  required VoidCallback onTogglePanel,
  required VoidCallback onSubmit,
  required VoidCallback onAttach,
  required VoidCallback onVoice,
  required VoidCallback onCancelEdit,
  ComposerHeader? suggestions,
  ComposerHeader? linkPreview,
  ComposerLinkPrompt? linkPrompt,
  ComposerBackPriority? backPriority,
  ComposerDeniedForms? deniedForms,
}) {
  final forms =
      deniedForms ??
      ComposerDeniedForms.forPlatform(defaultTargetPlatform, isWeb: kIsWeb);
  final composer = strings.composer;
  final isEditing = editing != null;
  return ComposerSpec(
    // A suggestion panel is open only while a token is, so it takes the strip
    // from an edit or a preview for that while; otherwise the edit outranks
    // the preview.
    header:
        suggestions ??
        ComposerHeader.prioritised([
          if (isEditing)
            ComposerHeader.edit(
              preview: editing.preview,
              onDismiss: onCancelEdit,
            ),
          linkPreview,
        ]),
    busy: busy,
    messageLengthLimit: messageLengthLimit,
    // The demo offers every item; lists are the second field's (the chat's
    // text controller keeps them off, and the menu leaves them out then).
    formatting: ComposerFormattingOption.all,
    linkPrompt: linkPrompt,
    backPriority: backPriority,
    actions: [
      ActionDescriptor(
        id: ChatComposerActions.panel,
        icon: panelReplacesKeyboard ? ChromeIconId.keyboard : pageIcon,
        semanticLabel: panelReplacesKeyboard
            ? composer.showKeyboardAction
            : composer.showPanelAction,
        placement: panelPlacement,
        active: panelDocked,
        wrap: wrapPanelToggle,
        // Where plain text denied dims the emoji toggle with the field (the
        // Android form), the toggle is the text right; not while it shows
        // the keyboard, which the locked field does not take.
        capability: forms.textDeniedDimsEmoji && !panelReplacesKeyboard
            ? CapabilityAction.sendText
            : null,
        onTap: onTogglePanel,
      ),
      ActionDescriptor(
        id: ChatComposerActions.attach,
        icon: ChromeIconId.attach,
        semanticLabel: composer.attachAction,
        // Where the panel is at the end (a desktop), attach takes the start
        // edge, before the field: attach, field,
        // panel, send. Where the panel is first (a phone) attach stays with
        // the voice and send actions at the end.
        placement: switch (panelPlacement) {
          ActionPlacement.trailing => ActionPlacement.leading,
          ActionPlacement.leading => ActionPlacement.trailing,
        },
        visible: !isEditing,
        // Its picker sends: held during slow mode where the platform holds it.
        heldBySlowMode: true,
        onTap: onAttach,
      ),
      switch (editing) {
        // An edit confirms, never records: a caption may be emptied, text
        // alone may not, and the emptied text's confirm is inert.
        final editing? => ActionDescriptor(
          id: ChatComposerActions.primary,
          icon: ChromeIconId.confirm,
          semanticLabel: composer.confirmEditAction,
          primary: editing.caption || hasText,
          onTap: editing.caption || hasText ? onSubmit : null,
        ),
        null => ActionDescriptor(
          id: ChatComposerActions.primary,
          icon: hasText ? ChromeIconId.send : ChromeIconId.voice,
          semanticLabel: hasText
              ? composer.sendAction
              : composer.recordVoiceAction,
          primary: hasText,
          // The voice button is the chat's voice right: dimmed and reporting
          // where the chat denies it.
          capability: hasText ? null : CapabilityAction.sendVoice,
          onTap: hasText ? onSubmit : onVoice,
        ),
      },
    ],
  );
}
