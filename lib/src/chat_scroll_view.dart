import 'package:chatscrollview/src/message.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ChatScrollChunk {
  /// The number of bits to shift to get the chunk index.
  static const int kChunkBits = 6;

  /// The max number of items in a chunk.
  static const int kChunkSize = 64;

  ChatScrollChunk({required this.index});

  /// The index of the chunk.
  final int index;

  /// The items in the chunk.
  final List<MessageEntity> items = [];
}

/// {@template chat_scroll_view}
/// ChatScrollView widget.
/// {@endtemplate}
class ChatScrollView extends RenderObjectWidget {
  /// {@macro chat_scroll_view}
  const ChatScrollView({
    required this.fetch,
    required this.builder,
    super.key, // ignore: unused_element_parameter
  });

  /// The function to fetch messages.
  final Future<List<MessageEntity>> Function({
    int? from,
    int? to,
    DateTime? after,
  })
  fetch;

  /// The function to build a message widget.
  final Widget Function(MessageEntity message) builder;

  @override
  RenderObjectElement createElement() {
    // TODO: implement createElement
    throw UnimplementedError();
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    // TODO: implement createRenderObject
    throw UnimplementedError();
  }
}

class ChatScrollViewElement extends RenderObjectElement {
  ChatScrollViewElement(super.widget);

  @override
  void insertRenderObjectChild(
    covariant RenderObject child,
    covariant Object? slot,
  ) {
    // TODO: implement insertRenderObjectChild
  }

  @override
  void moveRenderObjectChild(
    covariant RenderObject child,
    covariant Object? oldSlot,
    covariant Object? newSlot,
  ) {
    // TODO: implement moveRenderObjectChild
  }

  @override
  void removeRenderObjectChild(
    covariant RenderObject child,
    covariant Object? slot,
  ) {
    // TODO: implement removeRenderObjectChild
  }
}

class ChatScrollViewRenderObject extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, Object>,
        RenderBoxContainerDefaultsMixin<RenderBox, Object> {
  ChatScrollViewRenderObject();

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;
}
