import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_element.dart';
import 'package:chatscrollview/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/widgets.dart';

/// Builds the widget for message [id].
///
/// [message] is `null` when the message is not loaded yet (its chunk is being
/// fetched) — return a shimmer/placeholder in that case. [status] reflects the
/// owning chunk's fetch state (dirty / fetching / error / valid).
typedef ChatMessageBuilder =
    Widget Function(
      BuildContext context,
      int id,
      IChatMessage? message,
      ChatMessageStatus status,
    );

/// Widget-based endless chat viewport.
///
/// Anchor-based (id-relative) layout: messages are positioned around
/// [ChatScrollController.anchorMessageId], never against a global content
/// height. Children are real widgets — built lazily during layout via a
/// custom [ChatScrollElement] and wrapped in [RepaintBoundary] for picture +
/// layer caching. Scrolling repositions cached layers without re-layout.
class ChatScrollView extends RenderObjectWidget {
  const ChatScrollView({
    required this.dataSource,
    required this.controller,
    required this.messageBuilder,
    this.cacheExtent = 250.0,
    this.keepAliveExtent = 0.0,
    super.key,
  });

  /// Owns message data, chunks, and the fetch contract.
  final ChatDataSource dataSource;

  /// Owns anchor state, conversation boundaries, and jumps.
  final ChatScrollController controller;

  /// Builds the widget for each message id. Pass a stable reference (a
  /// top-level function or a cached closure) — a new closure each parent
  /// rebuild forces every visible message to re-inflate.
  final ChatMessageBuilder messageBuilder;

  /// Pixels above and below the viewport to keep built.
  final double cacheExtent;

  /// Extra pixels beyond [cacheExtent] where message widgets stay mounted
  /// while off-screen (paint-culled), so their `State` survives a scroll out
  /// and back. `0` (the default) collects children as soon as they leave the
  /// cache extent.
  final double keepAliveExtent;

  @override
  RenderObjectElement createElement() => ChatScrollElement(this);

  @override
  RenderChatScrollView createRenderObject(BuildContext context) =>
      RenderChatScrollView(
        dataSource: dataSource,
        controller: controller,
        cacheExtent: cacheExtent,
        keepAliveExtent: keepAliveExtent,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChatScrollView renderObject,
  ) {
    renderObject
      ..dataSource = dataSource
      ..controller = controller
      ..cacheExtent = cacheExtent
      ..keepAliveExtent = keepAliveExtent;
  }
}
