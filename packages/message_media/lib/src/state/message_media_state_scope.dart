import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/state/media_state_op.dart';
import 'package:message_media/src/state/message_media_state.dart';

/// Provides the chat's [MessageMediaState] to the cells below it.
///
/// The host owns and disposes the state; the scope only exposes it.
class MessageMediaStateScope extends InheritedWidget {
  /// Provides [state] to [child] and below.
  const MessageMediaStateScope({
    required this.state,
    required super.child,
    super.key,
  });

  /// The chat's state.
  final MessageMediaState state;

  /// The state of the nearest scope; asserts when there is none.
  static MessageMediaState of(BuildContext context) {
    final state = maybeOf(context);
    assert(state != null, 'No MessageMediaStateScope above this context.');
    return state!;
  }

  /// The state of the nearest scope, or null.
  static MessageMediaState? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MessageMediaStateScope>()
      ?.state;

  @override
  bool updateShouldNotify(MessageMediaStateScope oldWidget) =>
      state != oldWidget.state;
}

/// Gives [builder] the chat's [MessageMediaState]: the scope's when there is
/// one, otherwise one of its own, kept while this widget lives and lost when
/// it is disposed.
///
/// The fallback is reported once (`media / stateScopeMissing`, with
/// [scrollId]).
class MessageMediaStateBuilder extends StatefulWidget {
  /// A cell's access to the state.
  const MessageMediaStateBuilder({
    required this.scrollId,
    required this.builder,
    super.key,
  });

  /// The engine's id of the message this cell paints, for the diagnostics.
  final String scrollId;

  /// Builds the cell with its state.
  final Widget Function(BuildContext context, MessageMediaState state) builder;

  @override
  State<MessageMediaStateBuilder> createState() =>
      _MessageMediaStateBuilderState();
}

class _MessageMediaStateBuilderState extends State<MessageMediaStateBuilder> {
  MessageMediaState? _local;

  @override
  void dispose() {
    _local?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scoped = MessageMediaStateScope.maybeOf(context);
    if (scoped != null) {
      // A scope that appeared above this cell takes over; the cell's own
      // state is not needed any more.
      _local?.dispose();
      _local = null;
      return widget.builder(context, scoped);
    }
    final local = _local ??= _createLocal();
    return widget.builder(context, local);
  }

  MessageMediaState _createLocal() {
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.media,
      MediaStateOp.stateScopeMissing,
      correlation: ChatCorrelation(scrollId: widget.scrollId),
    );
    return MessageMediaState();
  }
}
