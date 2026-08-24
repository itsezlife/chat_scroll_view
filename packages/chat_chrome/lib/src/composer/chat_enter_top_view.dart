import 'package:chat_chrome/src/theme/chat_chrome_colors.dart';
import 'package:flutter/material.dart';

/// Reply / edit strip above the composer.
class ChatEnterTopView extends StatelessWidget {
  /// Creates a reply/edit chrome row.
  const ChatEnterTopView({
    required this.title,
    required this.subtitle,
    required this.onClose,
    this.isEdit = false,
    super.key,
  });

  /// Painted height — 48dp painted height.
  static const double barHeight = 48;

  /// Author name or "Edit message".
  final String title;

  /// Preview body text.
  final String subtitle;

  /// Whether this is an edit (vs reply) presentation.
  final bool isEdit;

  /// Close / cancel callback.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    return SizedBox(
      height: barHeight,
      child: Material(
        color: colors.messagePanelBackground,
        child: Row(
          children: <Widget>[
            const SizedBox(width: 18),
            Container(
              width: 2,
              height: 36,
              decoration: BoxDecoration(
                color: colors.replyLine,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              isEdit ? Icons.edit_rounded : Icons.reply_rounded,
              size: 20,
              color: colors.replyLine,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.replyName,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.replyText,
                      fontSize: 13,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 48,
              height: 46,
              child: IconButton(
                onPressed: onClose,
                icon: Icon(
                  Icons.close_rounded,
                  color: colors.messagePanelIcons,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
