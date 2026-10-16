import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_linkify_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows what a long press on a link offers: open it, or copy it.
///
/// [onOpen] runs after the sheet closes; [onCopied] with the copied text.
Future<void> showLinkActionsSheet(
  BuildContext context, {
  required String title,
  required String url,
  required VoidCallback onOpen,
  required ValueChanged<String> onCopied,
}) {
  final activation = ChatBodyLinkifyUtil.activation(url);
  final openLabel = switch (activation) {
    WebLinkActivation() => 'Open link',
    MentionLinkActivation() => 'Open mention',
    OtherLinkActivation() => 'Open',
  };
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty && title != url)
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                Text(
                  url,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(switch (activation) {
              MentionLinkActivation() => Icons.person_outline,
              WebLinkActivation() ||
              OtherLinkActivation() => Icons.open_in_browser,
            }),
            title: Text(openLabel),
            onTap: () {
              Navigator.pop(context);
              onOpen();
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(switch (activation) {
              MentionLinkActivation() => 'Copy mention',
              WebLinkActivation() || OtherLinkActivation() => 'Copy link URL',
            }),
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: url));
              onCopied(url);
            },
          ),
        ],
      ),
    ),
  );
}

/// Asks for the message corner radius (0 to 17), starting from [initial];
/// null when cancelled.
Future<double?> showBubbleRadiusDialog(
  BuildContext context, {
  required double initial,
}) => showDialog<double>(
  context: context,
  requestFocus: false,
  builder: (dialogContext) {
    var value = initial;
    return StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Message corners'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('${value.round()}'),
            Slider(
              value: value,
              min: 0,
              max: 17,
              divisions: 17,
              label: '${value.round()}',
              onChanged: (next) => setDialogState(() => value = next),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(value),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  },
);
