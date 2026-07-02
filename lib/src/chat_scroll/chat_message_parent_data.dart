import 'package:chatscrollview/src/chat_scroll/chat_extent_animation.dart';
import 'package:flutter/rendering.dart';

/// Parent data for a viewport child.
///
/// For a message: its [id], the [offset] of its top edge within the viewport
/// (viewport-local Y, may be negative), whether it [startsDay] (carries an
/// inline date divider), its [dayBucket] (day-grouping key, `null` until the
/// message loads), and the [dividerOpacity] of its inline date separator. The
/// floating day header reuses this type — only [offset] is meaningful for it.
class ChatMessageParentData extends ParentData {
  /// Message id this render box represents; `0` for the floating day header.
  int id = 0;

  /// Viewport-local Y of this child's top edge; may be negative when scrolled
  /// off-screen.
  double offset = 0;

  /// `true` when this message carries an inline day separator above its body.
  bool startsDay = false;

  /// Group key (`DateTime`, record, string, anything equatable) — produced by
  /// the viewport's `groupBy` callback. `null` when the message has not loaded
  /// or grouping is disabled.
  Object? dayBucket;

  /// Fade opacity (0..1) for this message's inline date separator — set by
  /// `RenderChatScrollView` from [offset] so the separator fades out as it
  /// rises into the floating day header's zone. Only meaningful when
  /// [startsDay] is `true`; read by `RenderDatedMessage`.
  double dividerOpacity = 1;

  /// Measured height after the last child [layout] — animation target.
  double targetHeight = 0;

  /// Vertical extent used for neighbor offset calculation during animation.
  double animatedHeight = 0;

  /// Active vertical spring; `null` when static.
  ExtentSpring? heightSpring;

  /// Message body opacity during insert/remove fade (1 = opaque).
  double opacity = 1;

  /// Active opacity curve run; `null` when static.
  CurveRun? opacityRun;

  /// Collapse in progress — child stays in tree until spring reaches zero.
  bool pendingRemoval = false;
}
