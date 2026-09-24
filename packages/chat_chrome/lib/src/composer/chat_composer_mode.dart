import 'package:flutter/foundation.dart';

/// Enter-island interaction mode (idle / edit / reply).
///
/// Mutually exclusive — an impossible idle+editing combination cannot exist.
@immutable
sealed class ChatComposerMode extends _$ChatComposerModeBase {
  const ChatComposerMode();

  /// {@macro chat_composer_mode_idle}
  const factory ChatComposerMode.idle() = ChatComposerMode$Idle;

  /// {@macro chat_composer_mode_editing}
  const factory ChatComposerMode.editing({
    required Object id,
    required String preview,
  }) = ChatComposerMode$Editing;

  /// {@macro chat_composer_mode_replying}
  const factory ChatComposerMode.replying({
    required Object id,
    required String title,
    required String subtitle,
  }) = ChatComposerMode$Replying;
}

/// {@template chat_composer_mode_idle}
/// No banner; composing a new message.
/// {@endtemplate}
@immutable
final class ChatComposerMode$Idle extends ChatComposerMode {
  /// {@macro chat_composer_mode_idle}
  const ChatComposerMode$Idle();

  @override
  String get type => 'idle';
}

/// {@template chat_composer_mode_editing}
/// Editing an existing message — [preview] feeds the top banner body.
/// {@endtemplate}
@immutable
final class ChatComposerMode$Editing extends ChatComposerMode {
  /// {@macro chat_composer_mode_editing}
  const ChatComposerMode$Editing({required this.id, required this.preview});

  /// Host message identity (opaque to chrome).
  final Object id;

  /// Marker-free preview for the banner subtitle.
  final String preview;

  @override
  String get type => 'editing';

  @override
  bool operator ==(Object other) =>
      other is ChatComposerMode$Editing &&
      other.id == id &&
      other.preview == preview;

  @override
  int get hashCode => Object.hash(id, preview);

  @override
  String toString() => 'ChatComposerMode.editing(id: $id, preview: $preview)';
}

/// {@template chat_composer_mode_replying}
/// Replying to a message — banner shows [title] / [subtitle].
/// {@endtemplate}
@immutable
final class ChatComposerMode$Replying extends ChatComposerMode {
  /// {@macro chat_composer_mode_replying}
  const ChatComposerMode$Replying({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  /// Host message identity (opaque to chrome).
  final Object id;

  /// Banner title (e.g. author name).
  final String title;

  /// Banner subtitle (e.g. message preview).
  final String subtitle;

  @override
  String get type => 'replying';

  @override
  bool operator ==(Object other) =>
      other is ChatComposerMode$Replying &&
      other.id == id &&
      other.title == title &&
      other.subtitle == subtitle;

  @override
  int get hashCode => Object.hash(id, title, subtitle);

  @override
  String toString() =>
      'ChatComposerMode.replying(id: $id, title: $title, subtitle: $subtitle)';
}

/// Pattern matching for [ChatComposerState].
typedef ChatComposerModeMatch<R, S extends ChatComposerMode> =
    R Function(S element);

@immutable
abstract base class _$ChatComposerModeBase {
  const _$ChatComposerModeBase();

  abstract final String type;

  /// Check if is Idle.
  bool get isIdle => this is ChatComposerMode$Idle;

  /// Check if is Editing.
  bool get isEditing => this is ChatComposerMode$Editing;

  /// Check if is Replying.
  bool get isReplying => this is ChatComposerMode$Replying;

  /// Pattern matching for [ChatComposerState].
  R map<R>({
    required ChatComposerModeMatch<R, ChatComposerMode$Idle> idle,
    required ChatComposerModeMatch<R, ChatComposerMode$Editing> editing,
    required ChatComposerModeMatch<R, ChatComposerMode$Replying> replying,
  }) => switch (this) {
    ChatComposerMode$Idle s => idle(s),
    ChatComposerMode$Editing s => editing(s),
    ChatComposerMode$Replying s => replying(s),
    _ => throw AssertionError(),
  };

  /// Pattern matching for [ChatComposerState].
  R maybeMap<R>({
    required R Function() orElse,
    ChatComposerModeMatch<R, ChatComposerMode$Idle>? idle,
    ChatComposerModeMatch<R, ChatComposerMode$Editing>? editing,
    ChatComposerModeMatch<R, ChatComposerMode$Replying>? replying,
  }) => map<R>(
    idle: idle ?? (_) => orElse(),
    editing: editing ?? (_) => orElse(),
    replying: replying ?? (_) => orElse(),
  );

  /// Pattern matching for [ChatComposerState].
  R? mapOrNull<R>({
    ChatComposerModeMatch<R, ChatComposerMode$Idle>? idle,
    ChatComposerModeMatch<R, ChatComposerMode$Editing>? editing,
    ChatComposerModeMatch<R, ChatComposerMode$Replying>? replying,
  }) => map<R?>(
    idle: idle ?? (_) => null,
    editing: editing ?? (_) => null,
    replying: replying ?? (_) => null,
  );

  @override
  String toString() => 'ChatComposerMode.$type';
}
