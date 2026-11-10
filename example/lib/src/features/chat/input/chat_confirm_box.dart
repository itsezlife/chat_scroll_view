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

/// A desktop confirmation box: a question and two text buttons, the
/// confirming one in the attention colour, in a box the pack box's width
/// over the pack box's dim, fading in and out over 200 ms.
///
/// Pushed in place of a pack box (`Navigator.pushReplacement`) the box is
/// swapped where it stands, on the same layer; pushed alone it stands over
/// the chat. Pops with true when confirmed, false or null otherwise.
final class ChatConfirmBoxRoute extends PopupRoute<bool> {
  /// A box asking [question], confirmed by [confirm] and dismissed by
  /// [cancel].
  ChatConfirmBoxRoute({
    required this.question,
    required this.confirm,
    required this.cancel,
  }) : super(requestFocus: true);

  /// What is asked.
  final String question;

  /// The confirming button's words.
  final String confirm;

  /// The dismissing button's words.
  final String cancel;

  static const Duration _fade = Duration(milliseconds: 200);

  @override
  Color get barrierColor => PackSheet.pointerBarrier;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => cancel;

  @override
  Duration get transitionDuration => _fade;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Center(
    child: SizedBox(
      width: PackSheet.boxWidth,
      child: _ConfirmBox(route: this),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

class _ConfirmBox extends StatelessWidget {
  const _ConfirmBox({required this.route});

  final ChatConfirmBoxRoute route;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    return Material(
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
              Padding(
                padding: const EdgeInsets.only(right: 12, bottom: 18),
                child: Text(
                  route.question,
                  style: TextStyle(color: palette.onSurface, fontSize: 14),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _Button(
                    label: route.cancel,
                    color: palette.accent,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  _Button(
                    label: route.confirm,
                    color: palette.destructive,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
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
