import 'package:chat_scroll_view/src/chat_scroll/chat_row_chrome_delegate.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_row_chrome.dart';
import 'package:flutter/widgets.dart';

/// A row whose only row chrome is an inline date separator above the message
/// body, fading under the floating day header.
///
/// Forwards to [ChatRowChrome] with a single
/// [ChatRowChromeDelegate.fadeUnderHeader] item; layout, paint, hit-testing,
/// and the viewport body-top contract are exactly [ChatRowChrome]'s.
@Deprecated(
  'Use ChatRowChrome with a ChatRowChromeItem whose delegate is '
  'ChatRowChromeDelegate.fadeUnderHeader().',
)
class DatedMessage extends ChatRowChrome {
  /// Stacks [separator] (fading under the floating day header) above [body].
  DatedMessage({required Widget separator, required super.body, super.key})
    : super(
        chrome: <ChatRowChromeItem>[
          ChatRowChromeItem(
            delegate: const ChatRowChromeDelegate.fadeUnderHeader(),
            child: separator,
          ),
        ],
      );
}

/// Render object behind [DatedMessage].
@Deprecated('Use RenderChatRowChrome.')
typedef RenderDatedMessage = RenderChatRowChrome;
