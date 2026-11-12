import 'package:bulletins/src/view/bulletin_builders.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// One bulletin drawn through [builders]: the frame around the content, with
/// the bulletin's semantics (a live region with its spoken label and a
/// dismiss action).
///
/// A bulletin host places, animates and handles gestures around it; the
/// card itself is the still picture.
class BulletinCard extends StatelessWidget {
  /// The card of [view] drawn by [builders].
  const BulletinCard({
    required this.view,
    this.builders = const BulletinBuilders(),
    super.key,
  });

  /// What is drawn.
  final BulletinView view;

  /// How it is drawn.
  final BulletinBuilders builders;

  @override
  Widget build(BuildContext context) {
    final content =
        builders.content?.call(context, view) ??
        BulletinBuilders.stockContent(context, view, builders);
    final framed =
        builders.frame?.call(context, view, content) ??
        BulletinBuilders.stockFrame(context, view, content);
    return Semantics(
      container: true,
      liveRegion: true,
      label: view.bulletin.spokenLabel,
      customSemanticsActions: {
        CustomSemanticsAction(label: view.strings.dismissAction):
            view.handle.dismiss,
      },
      child: framed,
    );
  }
}
