import 'package:chat_chrome/src/theme/chat_chrome_colors.dart';
import 'package:flutter/material.dart';

/// Empty sticker-pack page (enabled via [KeyboardPanelAllow.stickers]).
class StickerPageStub extends StatelessWidget {
  /// Creates the stub.
  const StickerPageStub({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.sticky_note_2_outlined,
              size: 56,
              color: colors.panelIcon,
            ),
            const SizedBox(height: 12),
            Text(
              'No stickers yet',
              style: TextStyle(
                color: colors.panelIconSelected,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sticker packs will appear here when available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.panelIcon, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty GIF page (enabled via [KeyboardPanelAllow.gifs]).
class GifPageStub extends StatelessWidget {
  /// Creates the stub.
  const GifPageStub({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.gif_box_outlined, size: 56, color: colors.panelIcon),
            const SizedBox(height: 12),
            Text(
              'No GIFs yet',
              style: TextStyle(
                color: colors.panelIconSelected,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'GIF search and trending will appear here when available.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.panelIcon, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
