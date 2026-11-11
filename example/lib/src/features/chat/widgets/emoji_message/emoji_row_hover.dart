import 'package:flutter/widgets.dart';

/// Whether a mouse is on the **row** of an emoji-only message: the whole cell
/// the viewport gives it, its end edge, its avatar gutter and its margins
/// included, not the emoji box.
///
/// On desktop the row alone decides it: the element under the cursor is found
/// by `y` and `x` is clamped to the list, and the media's info display shows the
/// time while that element is under the cursor. A region around the box would hide
/// the time again on the empty side of the row, where the pointer rests most of
/// the time.
///
/// Put it outside everything that sizes the row to its content, so its box is
/// the cell's.
class EmojiRowHover extends StatefulWidget {
  /// Builds the row, told whether a mouse is on it.
  const EmojiRowHover({required this.builder, super.key});

  /// The row; [hovered] is true while a mouse is anywhere on it.
  final Widget Function(BuildContext context, {required bool hovered}) builder;

  @override
  State<EmojiRowHover> createState() => _EmojiRowHoverState();
}

class _EmojiRowHoverState extends State<EmojiRowHover> {
  bool _hovered = false;

  void _set({required bool hovered}) {
    if (_hovered != hovered) setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    // Translucent: the empty side of the row has no child to hit, and the
    // regions around the row (the viewport's own) must still see the pointer.
    opaque: false,
    hitTestBehavior: HitTestBehavior.translucent,
    onEnter: (_) => _set(hovered: true),
    onExit: (_) => _set(hovered: false),
    child: widget.builder(context, hovered: _hovered),
  );
}
