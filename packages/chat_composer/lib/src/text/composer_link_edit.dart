import 'package:chat_composer/src/spec/composer_spec.dart';
import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:content_model/content_model.dart' show RichText;
import 'package:flutter/widgets.dart' hide RichText;

/// One ask for a link's URL over the selection, and the apply that follows.
///
/// The selection menu's link item and the link shortcut both run it, so the two
/// ways to a link are one protocol. It snapshots the text, the selection and
/// the URL the selection already carries when it is made; [ask] shows the
/// host's prompt and applies the answer to the selection as it was. The
/// prompt is modal and takes time: a text that changed under it is another
/// text, so the answer is dropped, and so it is when the view has gone.
final class ComposerLinkEdit {
  /// An ask over the selection of [text] now, through [prompt] on [context];
  /// with a [target], over the link at that extent instead, and the selection
  /// is not touched.
  ///
  /// [isAlive] says whether the view is still there when the prompt completes.
  ComposerLinkEdit({
    required ComposerTextController text,
    required ComposerLinkPrompt prompt,
    required BuildContext context,
    required bool Function() isAlive,
    TextRange? target,
  }) : _text = text,
       _prompt = prompt,
       _context = context,
       _isAlive = isAlive,
       _asked = text.richText,
       _selection = text.selection,
       _target = target,
       currentUrl = target == null
           ? text.selectedLinkUrl
           : text.linkAt(target.start)?.url;

  final ComposerTextController _text;
  final ComposerLinkPrompt _prompt;
  final BuildContext _context;
  final bool Function() _isAlive;
  final RichText _asked;
  final TextSelection _selection;
  final TextRange? _target;

  /// The target of the link the selection touched when the ask was made, or
  /// null when it touched none.
  final String? currentUrl;

  /// Shows the prompt and links the selection to the URL it completes with;
  /// nothing happens when it is cancelled, or when the view or the text is no
  /// longer what was asked about.
  Future<void> ask() async {
    if (!_isAlive()) return;
    final url = await _prompt(_context, currentUrl);
    if (url == null || !_isAlive() || _text.richText != _asked) return;
    if (_target case final target?) {
      // The link under the pointer: edited where it is, the selection left
      // as it was.
      _text.applyLinkTo(target, url);
      return;
    }
    _text.selection = _selection;
    _text.applyLink(url);
  }
}
