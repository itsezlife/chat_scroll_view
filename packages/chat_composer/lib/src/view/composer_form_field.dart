import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chat_composer/src/menu/composer_formatting_option.dart';
import 'package:chat_composer/src/menu/composer_menu_policy.dart';
import 'package:chat_composer/src/menu/composer_spell_checker.dart';
import 'package:chat_composer/src/shortcuts/composer_formatting_actions.dart';
import 'package:chat_composer/src/shortcuts/composer_intents.dart';
import 'package:chat_composer/src/spec/composer_spec.dart';
import 'package:chat_composer/src/view/composer_field.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart' hide RichText;

/// The composer's field in a host's form: the same editable, entities, lists,
/// selection menu and formatting keys as the chat island, under the host's
/// [InputDecoration] and inside Flutter's [Form] machinery.
///
/// A `FormField<RichText>`, as `TextFormField` is a `FormField<String>`: the
/// value is [ComposerController.richText], the [validator] reads it, `reset`
/// restores the text the field was built with, and the validator's error is
/// drawn in the decoration. Without a validator the decoration's own
/// `errorText` shows, for a host whose form state lives elsewhere.
///
/// **Input.** The text, focus and selection are the [controller]'s: give it a
/// `ComposerTextController(lists: true)` for lists and a `focusNode` to move
/// focus from outside. The host sets the text controller's `entityStyles`
/// (usually `ComposerEntityStyles.fromTokens` of the chrome theme) and
/// disposes the controller.
///
/// **Menu.** [formatting] is the set of items the selection menu offers, as
/// `ComposerSpec.formatting`: the list items need lists on, the link items
/// need [linkPrompt]. [backPriority] takes Back ahead of the soft keyboard
/// while the menu is open.
///
/// **Length.** [maxLength] is a budget in code points of the plain text
/// (`ComposerController.length`, the unit of `ComposerSpec.messageLengthLimit`):
/// the decoration counts `length/maxLength`, and past it the counter and the
/// border take the error colour. Nothing is trimmed or refused, as in the
/// island; a host that must not save over the budget says so in its
/// [validator].
///
/// **Keys.** The formatting and list keys of the platform's
/// `ComposerShortcutPolicy` apply, without submit and header dismissal: Enter
/// is a newline in a form. [shortcuts] replaces them.
///
/// Needs, as `ComposerView` does, a `ChromeThemeScope`, a `ChromeStringsScope`,
/// a `MediaQuery`, Material localisations and a Material ancestor.
class ComposerFormField extends FormField<RichText> {
  /// A form field over [controller].
  ComposerFormField({
    required this.controller,
    this.decoration = const InputDecoration(),
    this.style,
    this.minLines,
    this.maxLines,
    this.textInputAction = TextInputAction.newline,
    this.textCapitalization = TextCapitalization.sentences,
    this.maxLength,
    this.buildCounter,
    this.autofocus = false,
    this.formatting = ComposerFormattingOption.standard,
    this.linkPrompt,
    this.backPriority,
    this.spellChecker,
    this.menuPolicy,
    this.shortcuts,
    this.onTap,
    super.validator,
    super.onSaved,
    super.forceErrorText,
    super.autovalidateMode,
    super.enabled,
    super.restorationId,
    super.key,
  }) : super(initialValue: controller.richText, builder: _build);

  /// The input state.
  final ComposerController controller;

  /// The host's decoration: label, hint, helper, borders, icons. The
  /// validator's error and the length counter are added to it.
  final InputDecoration? decoration;

  /// The text style, merged over the theme's text field style.
  final TextStyle? style;

  /// The fewest lines the field shows.
  final int? minLines;

  /// The most lines it grows to before it scrolls; null grows with the text.
  final int? maxLines;

  /// The soft keyboard's action key.
  final TextInputAction textInputAction;

  /// How the soft keyboard capitalises.
  final TextCapitalization textCapitalization;

  /// The length budget in code points of the plain text; null is none.
  final int? maxLength;

  /// Builds the counter instead of `length/maxLength`, as
  /// `TextField.buildCounter` does; `currentLength` is in code points.
  final InputCounterWidgetBuilder? buildCounter;

  /// Whether the field takes focus when first built.
  final bool autofocus;

  /// The formatting items the selection menu may offer.
  final Set<ComposerFormattingOption> formatting;

  /// The host's link dialog; without it there is no link item.
  final ComposerLinkPrompt? linkPrompt;

  /// The host's hook for taking Back ahead of the soft keyboard while the
  /// selection menu is open.
  final ComposerBackPriority? backPriority;

  /// The pointer menu's spell checker.
  final ComposerSpellChecker? spellChecker;

  /// How the field presents its menu; null follows the platform.
  final ComposerMenuPolicy? menuPolicy;

  /// Key bindings; null is the platform's formatting and list keys.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// Called when the field is tapped.
  final VoidCallback? onTap;

  static Widget _build(FormFieldState<RichText> field) =>
      (field as _ComposerFormFieldState)._buildField();

  @override
  FormFieldState<RichText> createState() => _ComposerFormFieldState();
}

class _ComposerFormFieldState extends FormFieldState<RichText> {
  @override
  ComposerFormField get widget => super.widget as ComposerFormField;

  ComposerController get _controller => widget.controller;

  late final Map<Type, Action<Intent>> _actions = ComposerFormattingActions.of(
    text: _controller.text,
    linkPrompt: () => widget.linkPrompt,
    context: () => context,
    isAlive: () => mounted,
  );

  @override
  void initState() {
    super.initState();
    _controller.text.addListener(_onText);
    _controller.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(ComposerFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      identical(oldWidget.controller, widget.controller),
      'A ComposerFormField keeps its controller: key the field to swap it.',
    );
  }

  @override
  void dispose() {
    _controller.text.removeListener(_onText);
    _controller.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  // The text controller notifies on every selection move too; the form hears
  // only a change of the rich text.
  void _onText() {
    final text = _controller.richText;
    if (text != value) didChange(text);
  }

  // A host counter is told whether the field is focused.
  void _onFocus() {
    if (widget.buildCounter != null) setState(() {});
  }

  @override
  void reset() {
    // The form's value goes back first, so the controller's notification
    // finds nothing to report.
    super.reset();
    _controller.restore(widget.initialValue ?? RichText.empty);
  }

  InputDecoration _decoration() {
    final theme = Theme.of(context);
    var decoration = (widget.decoration ?? const InputDecoration()).copyWith(
      errorText: errorText ?? widget.decoration?.errorText,
    );
    final limit = widget.maxLength;
    if (limit == null) return decoration;
    final length = _controller.length;
    final counter = widget.buildCounter?.call(
      context,
      currentLength: length,
      maxLength: limit,
      isFocused: _controller.focusNode.hasFocus,
    );
    decoration = counter != null
        ? decoration.copyWith(counter: counter)
        : decoration.counter != null || decoration.counterText != null
        ? decoration
        : decoration.copyWith(counterText: '$length/$limit');
    // Over the budget the field looks as a stock text field with an
    // unenforced maxLength does: an error border and an error-coloured
    // counter, with the error text the host's (or none).
    if (length <= limit) return decoration;
    return decoration.copyWith(
      errorText: decoration.errorText ?? '',
      counterStyle:
          decoration.errorStyle ??
          theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
    );
  }

  Map<ShortcutActivator, Intent> get _shortcuts {
    if (widget.shortcuts case final shortcuts?) return shortcuts;
    // A form has no send and no header: Enter stays the field's newline and
    // Escape is left to the route.
    return Map.of(
      ComposerShortcutPolicy.forPlatform(
        defaultTargetPlatform,
        isWeb: kIsWeb,
      ).shortcuts,
    )..removeWhere(
      (_, intent) =>
          intent is SubmitComposerIntent ||
          intent is DismissComposerHeaderIntent,
    );
  }

  Widget _buildField() => Shortcuts(
    shortcuts: _shortcuts,
    child: Actions(
      actions: _actions,
      child: ComposerField(
        controller: _controller,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        formatting: widget.formatting,
        linkPrompt: widget.linkPrompt,
        backPriority: widget.backPriority,
        spellChecker: widget.spellChecker,
        menuPolicy: widget.menuPolicy,
        onTap: widget.onTap,
        layout: ComposerFieldLayout.form(
          decoration: _decoration(),
          style: widget.style,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          textInputAction: widget.textInputAction,
          textCapitalization: widget.textCapitalization,
        ),
      ),
    ),
  );
}
