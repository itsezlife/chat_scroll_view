import 'package:chat_composer/src/shortcuts/composer_formatting_intents.dart';
import 'package:chat_composer/src/spec/composer_spec.dart';
import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// The Actions that answer the formatting Intents.
///
/// Each one calls the [ComposerTextController] command the selection menu
/// calls, so a shortcut and a menu item give the same [RichText]; `isEnabled`
/// follows `canApply`, so a key that would change nothing is left to the field.
///
/// The list Intent has no Action yet: it waits for the list commands, and
/// until then the key it is bound to is left to the field.
abstract final class ComposerFormattingActions {
  /// The Actions over [text], keyed by the Intent they answer.
  ///
  /// [linkPrompt] and [context] are read when the link Intent fires, since the
  /// host rebuilds its spec; [isAlive] says whether the view is still there
  /// when the prompt completes.
  static Map<Type, Action<Intent>> of({
    required ComposerTextController text,
    required ComposerLinkPrompt? Function() linkPrompt,
    required BuildContext Function() context,
    required bool Function() isAlive,
  }) => {
    ToggleStyleIntent: _ToggleStyleAction(text),
    ToggleCodeBlockIntent: _ToggleCodeBlockAction(text),
    ClearFormattingIntent: _ClearFormattingAction(text),
    ApplyLinkIntent: _ApplyLinkAction(text, linkPrompt, context, isAlive),
  };
}

class _ToggleStyleAction extends Action<ToggleStyleIntent> {
  _ToggleStyleAction(this._text);

  final ComposerTextController _text;

  @override
  bool isEnabled(ToggleStyleIntent intent) =>
      _text.canApply(EntityKind.style(intent.style));

  @override
  Object? invoke(ToggleStyleIntent intent) {
    _text.toggleStyle(intent.style);
    return null;
  }
}

class _ToggleCodeBlockAction extends Action<ToggleCodeBlockIntent> {
  _ToggleCodeBlockAction(this._text);

  final ComposerTextController _text;

  @override
  bool isEnabled(ToggleCodeBlockIntent intent) =>
      _text.canApply(const EntityKind.codeBlock());

  @override
  Object? invoke(ToggleCodeBlockIntent intent) {
    _text.toggleCodeBlock();
    return null;
  }
}

class _ClearFormattingAction extends Action<ClearFormattingIntent> {
  _ClearFormattingAction(this._text);

  final ComposerTextController _text;

  @override
  bool isEnabled(ClearFormattingIntent intent) => _text.canClearFormatting;

  @override
  Object? invoke(ClearFormattingIntent intent) {
    _text.clearFormatting();
    return null;
  }
}

class _ApplyLinkAction extends Action<ApplyLinkIntent> {
  _ApplyLinkAction(this._text, this._prompt, this._context, this._isAlive);

  final ComposerTextController _text;
  final ComposerLinkPrompt? Function() _prompt;
  final BuildContext Function() _context;
  final bool Function() _isAlive;

  // The dialog is modal, but a second key press can arrive before it shows.
  var _asking = false;

  // `canApply` for a link wants a URL to judge it and reports no change for the
  // one the selection is linked to already. The refusals it reports (code, a
  // mention, a composition) do not depend on which, so the probe differs from
  // the current one.
  EntityKind get _probe {
    final current = _text.selectedLinkUrl;
    return EntityKind.link(
      current == null ? 'https://example.com' : '$current#',
    );
  }

  @override
  bool isEnabled(ApplyLinkIntent intent) =>
      !_asking && _prompt() != null && _text.canApply(_probe);

  @override
  Future<void> invoke(ApplyLinkIntent intent) async {
    final prompt = _prompt();
    if (prompt == null) return;
    final asked = _text.richText;
    final selection = _text.selection;
    _asking = true;
    final String? url;
    try {
      url = await prompt(_context(), _text.selectedLinkUrl);
    } finally {
      _asking = false;
    }
    // The prompt took time; a text that changed under it is another text.
    if (url == null || !_isAlive() || _text.richText != asked) return;
    _text.selection = selection;
    _text.applyLink(url);
  }
}
