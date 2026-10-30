import 'package:flutter/cupertino.dart';

/// The route a chat is pushed with from the chat list: the iOS slide with
/// its parallax and edge-swipe back, over a page that keeps painting.
///
/// Mirrors the route the product this demo measures against opens its chats
/// with, because the cost of opening a chat is mostly what the transition
/// makes the wallpaper, the glass and the first rows do:
///
/// - **Not opaque.** The chat list goes on painting under the sliding chat,
///   as it does in the product, so a suite measures both layers.
/// - **220 ms** both ways, shorter than the platform's 500 ms: long enough
///   to read as a slide, short enough that a slow first frame shows as a
///   visible hitch rather than hiding in the curve.
class ChatPageRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T> {
  /// Pushes [builder]'s chat.
  ChatPageRoute({required this.builder, super.settings});

  /// Builds the chat.
  final WidgetBuilder builder;

  /// Length of the push and the pop.
  static const Duration duration = Duration(milliseconds: 220);

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  String? get title => null;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration;
}
