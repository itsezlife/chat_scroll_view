import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';
import 'package:panel_pages/panel_pages.dart' show PackSheet;

/// The words of the confirmation before a pack is removed on a desktop.
///
/// [english] holds the English texts; [russian] is the demo's language.
@immutable
final class ChatConfirmStrings {
  /// A set of every text.
  const ChatConfirmStrings({
    required this.removePack,
    required this.removeAction,
    required this.cancelAction,
  });

  /// The English texts.
  static const ChatConfirmStrings english = ChatConfirmStrings(
    removePack: _englishRemovePack,
    removeAction: 'Remove',
    cancelAction: 'Cancel',
  );

  /// The demo's Russian.
  static const ChatConfirmStrings russian = ChatConfirmStrings(
    removePack: _russianRemovePack,
    removeAction: 'Удалить',
    cancelAction: 'Отмена',
  );

  /// The set the demo shows.
  static const ChatConfirmStrings demo = russian;

  /// The question before the pack titled with the argument is removed.
  final String Function(String title) removePack;

  /// The button that removes it.
  final String removeAction;

  /// The button that keeps it.
  final String cancelAction;
}

String _englishRemovePack(String title) => 'Remove «$title»?';

String _russianRemovePack(String title) => 'Удалить «$title»?';

/// A desktop confirmation box: an optional bold [title], a question and two
/// text buttons, the confirming one in the attention colour, as wide as the
/// pack box.
///
/// A box of a `ChromeBoxLayer`: shown from a pack box
/// (`ChromeBoxLayer.of(context).show`) it takes that box's place at once,
/// and the pack box comes back when it closes; opened alone ([open]) it is
/// the only box of its own layer over the chat. Its buttons pop it with true
/// (confirmed) or false; Escape pops it with null.
class ChatConfirmBox extends StatelessWidget {
  /// A box asking [question], confirmed by [confirm] and dismissed by
  /// [cancel].
  const ChatConfirmBox({
    required this.question,
    required this.confirm,
    required this.cancel,
    this.title,
    super.key,
  });

  /// How long the box's own layer takes to fade in or out.
  static const Duration fade = Duration(milliseconds: 200);

  /// Opens [box] alone on a layer of its own over [context], over the pack
  /// box's dim; completes with what it was answered with.
  static Future<bool> open(BuildContext context, ChatConfirmBox box) async =>
      await ChromeBoxLayer.open<bool>(
        context,
        barrierColor: PackSheet.pointerBarrier,
        barrierLabel: box.cancel,
        transitionDuration: fade,
        builder: (_) => box,
      ) ??
      false;

  /// The line above the question, or null for none.
  final String? title;

  /// What is asked.
  final String question;

  /// The confirming button's words.
  final String confirm;

  /// The dismissing button's words.
  final String cancel;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    return SizedBox(
      width: PackSheet.boxWidth,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title case final title?)
                  Padding(
                    padding: const EdgeInsets.only(right: 12, bottom: 12),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 18),
                  child: Text(
                    question,
                    style: TextStyle(color: palette.onSurface, fontSize: 14),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _Button(
                      label: cancel,
                      color: palette.accent,
                      onTap: () => Navigator.of(context).pop(false),
                    ),
                    _Button(
                      label: confirm,
                      color: palette.destructive,
                      onTap: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: ChromeInk(
      color: color.withAlpha(0x24),
      hoverColor: color.withAlpha(0x12),
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}
