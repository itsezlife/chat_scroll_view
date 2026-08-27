import 'package:flutter/widgets.dart';
import 'package:message_media/src/grouped_messages.dart';
import 'package:message_media/src/mosaic_layout.dart';

/// Plain-text caption slot on the caption-owning group row.
///
/// Owns: caption string, vertical placement relative to media, reserved
/// height. Does not own: entities, spoilers, rich text layout, or measure —
/// the host (or [GroupRowLayout.compute]) supplies [height].
final class GroupCaptionSlot {
  /// Creates a caption slot with [text] of reserved [height].
  ///
  /// When [above] is true, the caption sits above the media
  /// ([GroupedMessages.captionAbove] / `invert_media`); otherwise below.
  const GroupCaptionSlot({
    required this.text,
    required this.above,
    required this.height,
  });

  /// Plain caption string (no entities). Empty when the host reserved height
  /// without supplying copy yet.
  final String text;

  /// `true` → caption above media; `false` → below.
  final bool above;

  /// Reserved height contributed only to the caption-owning group row.
  final double height;
}

/// One group row’s media height plus optional caption contribution.
///
/// [mediaHeight] is the mosaic cell height for this Message ID. [totalHeight]
/// adds [caption.height] only when this row owns the group caption; sibling
/// rows stay geometry-only.
final class GroupRowHeights {
  /// Creates heights for one member index in the group.
  const GroupRowHeights({
    required this.mediaHeight,
    required this.totalHeight,
    this.caption,
  });

  /// Pixel height of this member’s mosaic cell (no caption).
  final double mediaHeight;

  /// Fan-out row height: [mediaHeight] plus [GroupCaptionSlot.height] when
  /// [caption] is non-null (including when that height is `0`).
  final double totalHeight;

  /// Caption slot when this index is [GroupedMessages.captionIndex];
  /// otherwise `null`.
  final GroupCaptionSlot? caption;
}

/// Derives per–group-row heights and caption placement from mosaic + calculate.
///
/// Owns: mapping [GroupedMessages.captionIndex] / [GroupedMessages.captionAbove]
/// onto one [GroupCaptionSlot] and per-index [GroupRowHeights]. Does not own:
/// text measure, chat fan-out, or placeholder paint.
///
/// ## Caption rules
///
/// - Only the index equal to [GroupedMessages.captionIndex] receives a slot
///   (Telegram `captionMessage` owner).
/// - When [captionIndex] is `null` (no caption or multiple captions cancelled),
///   every row is media-only even if [captionText] / [captionHeight] are set.
/// - [captionHeight] is added only to the owning row’s [GroupRowHeights.totalHeight];
///   sibling mosaic heights are unchanged.
/// - A non-null [captionIndex] always yields a slot; [captionText] defaults to
///   `''` when omitted so height can be reserved before copy is ready.
///
/// [mosaic].cells and [messages].positions MUST be the same length and order.
final class GroupRowLayout {
  GroupRowLayout._();

  /// Computes one [GroupRowHeights] per mosaic cell / member index.
  ///
  /// [captionText] is the plain string for the sole caption owner (from
  /// [GroupedMessagesEntry.captionText] or host measure). Ignored when
  /// [GroupedMessages.captionIndex] is `null`. Defaults to empty when the
  /// index is set but text is omitted.
  ///
  /// [captionHeight] is the reserved band height for that owner (default `0`);
  /// only that index’s [GroupRowHeights.totalHeight] includes it.
  ///
  /// Preconditions: [mosaic].cells.length == [messages].positions.length and
  /// same member order; violated in debug via assert.
  static List<GroupRowHeights> compute({
    required MosaicLayout mosaic,
    required GroupedMessages messages,
    String? captionText,
    double captionHeight = 0,
  }) {
    final cells = mosaic.cells;
    assert(
      cells.length == messages.positions.length,
      'Mosaic cells and calculate positions must match in length',
    );

    final captionIndex = messages.captionIndex;
    final above = messages.captionAbove;

    return [
      for (var i = 0; i < cells.length; i++)
        _rowAt(
          index: i,
          mediaHeight: cells[i].rect.height,
          captionIndex: captionIndex,
          captionAbove: above,
          captionText: captionText,
          captionHeight: captionHeight,
        ),
    ];
  }

  static GroupRowHeights _rowAt({
    required int index,
    required double mediaHeight,
    required int? captionIndex,
    required bool captionAbove,
    required String? captionText,
    required double captionHeight,
  }) {
    final slot = switch (captionIndex) {
      final i? when i == index => GroupCaptionSlot(
        text: captionText ?? '',
        above: captionAbove,
        height: captionHeight,
      ),
      _ => null,
    };
    final extra = switch (slot) {
      GroupCaptionSlot(:final height) => height,
      null => 0.0,
    };
    return GroupRowHeights(
      mediaHeight: mediaHeight,
      totalHeight: mediaHeight + extra,
      caption: slot,
    );
  }
}

/// Stacks optional plain caption text above or below a media [child].
///
/// Owns: vertical order from [GroupCaptionSlot.above] and a caption band of
/// exactly [GroupCaptionSlot.height] logical pixels. Does not own: mosaic
/// geometry, entities, or host theme — [style] defaults to a muted light grey
/// suitable for placeholder chats.
///
/// When [caption] is `null`, builds only [child]. When [GroupCaptionSlot.height]
/// is `0`, the band collapses (no layout growth). Text is clipped to the band
/// with at most three lines and [TextOverflow.ellipsis].
final class GroupRowCaption extends StatelessWidget {
  /// Creates a caption + media stack for one group row.
  const GroupRowCaption({
    super.key,
    required this.child,
    this.caption,
    this.style = const TextStyle(
      color: Color(0xFFE8E8ED),
      fontSize: 14,
      height: 1.2,
    ),
  });

  /// Media surface for this group row (placeholder or bound image).
  final Widget child;

  /// Caption slot from [GroupRowLayout]; `null` → media only.
  final GroupCaptionSlot? caption;

  /// Plain-text style (no entity spans).
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (caption case final slot?) {
      final text = SizedBox(
        height: slot.height,
        width: double.infinity,
        child: slot.height <= 0
            ? const SizedBox.shrink()
            : Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  slot.text,
                  style: style,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [if (slot.above) text, child, if (!slot.above) text],
      );
    }
    return child;
  }
}
