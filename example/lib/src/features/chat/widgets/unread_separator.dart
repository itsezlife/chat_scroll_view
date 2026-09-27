import 'package:flutter/widgets.dart';

/// Unread-messages bar for the demo chat: a full-width strip with a centered
/// label, built by `ChatScrollView.unreadSeparatorBuilder` above the first
/// unread incoming message.
class UnreadSeparator extends StatelessWidget {
  /// Builds the bar. The label carries no count.
  const UnreadSeparator({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 6),
    child: DecoratedBox(
      decoration: BoxDecoration(color: Color(0x99202124)),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            'Непрочитанные сообщения',
            style: TextStyle(
              color: Color(0xFFE6E6E6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );
}
