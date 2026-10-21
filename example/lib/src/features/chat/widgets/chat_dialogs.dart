import 'package:chat_scroll_view_example/src/features/chat/utils/link_activation.dart';
import 'package:content_model/content_model.dart'
    show PastedMedia, PastedMedia$Bytes, PastedMedia$File;
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
  final activation = LinkActivation.fromUrl(url);
  final openLabel = switch (activation) {
    WebLinkActivation() => 'Open link',
    MentionLinkActivation() || UsernameLinkActivation() => 'Open profile',
    HashtagLinkActivation() => 'Search hashtag',
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
              MentionLinkActivation() ||
              UsernameLinkActivation() => Icons.person_outline,
              HashtagLinkActivation() => Icons.tag,
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
              MentionLinkActivation() ||
              UsernameLinkActivation() => 'Copy mention',
              HashtagLinkActivation() => 'Copy hashtag',
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

/// Shows what a paste of media would send: each image, each file by name.
/// Completes with whether the user chose to send. The demo sends no media,
/// so the caller only reports the choice.
Future<bool> showPastedMediaSheet(
  BuildContext context,
  List<PastedMedia> media,
) async {
  final send = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              media.length == 1 ? 'Send 1 item' : 'Send ${media.length} items',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: media.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _PastedMediaTile(media[index]),
            ),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return send ?? false;
}

class _PastedMediaTile extends StatelessWidget {
  const _PastedMediaTile(this.media);

  final PastedMedia media;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox.square(
      dimension: 120,
      child: switch (media) {
        PastedMedia$Bytes(:final bytes, :final mimeType)
            when mimeType.startsWith('image/') =>
          Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (context, _, _) => const _FileTile('image'),
          ),
        PastedMedia$Bytes(:final name, :final mimeType) => _FileTile(
          name ?? mimeType,
        ),
        PastedMedia$File(:final path) => _FileTile(
          path.split(RegExp(r'[/\\]')).last,
        ),
      },
    ),
  );
}

class _FileTile extends StatelessWidget {
  const _FileTile(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.insert_drive_file_outlined),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
