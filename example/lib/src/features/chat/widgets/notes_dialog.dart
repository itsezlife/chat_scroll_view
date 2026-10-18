import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' show RichClipboard;
import 'package:flutter/material.dart';

/// Shows the demo's notes field.
///
/// The chat's composer keeps lists off, as a chat does; this is the one field
/// of the demo that edits them (`ComposerTextController(lists: true)`): typed
/// `- `, `* ` and `1. ` markers, Enter, Backspace and Tab in an item, and the
/// Bullet and Numbered items of the selection menu.
Future<void> showNotesDialog(
  BuildContext context, {
  required RichClipboard clipboard,
}) => showDialog<void>(
  context: context,
  builder: (context) => _NotesDialog(clipboard: clipboard),
);

class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.clipboard});

  final RichClipboard clipboard;

  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  late final ComposerController _composer = ComposerController(
    text: ComposerTextController(lists: true),
    clipboard: widget.clipboard,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _composer.text.entityStyles = ComposerEntityStyles.fromTokens(
      ChromeThemeScope.composerOf(context),
    );
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Text('Notes', style: TextStyle(fontSize: 20)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                'Lists are on here: start a line with "- " or "1. ".',
              ),
            ),
            const Spacer(),
            ComposerView(
              controller: _composer,
              safeAreaBottom: 0,
              spec: ComposerSpec(
                formatting: ComposerFormattingOption.all,
                linkPrompt: ChatInputSet.linkPromptOver(widget.clipboard),
                backPriority: ChatInputSet.claimBack,
                actions: [
                  ActionDescriptor(
                    id: 'close',
                    icon: ChromeIconId.close,
                    semanticLabel: strings.panel.cancelAction,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
