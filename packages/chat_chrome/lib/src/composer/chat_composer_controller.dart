import 'package:chat_chrome/src/composer/chat_composer_mode.dart';
import 'package:chat_chrome/src/composer/chat_enter_icons.dart';
import 'package:chat_chrome/src/panel/keyboard_panel.dart' show emojiBackspace;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Host-owned chrome source of truth for the composer enter island.
final class ChatComposerController extends ValueNotifier<ChatComposerState> {
  /// Creates composer SoT.
  ChatComposerController({
    TextEditingController? text,
    FocusNode? focusNode,
    ScrollController? fieldScroll,
    bool? ownsText,
    bool enabled = true,
  }) : _text = text ?? TextEditingController(),
       _ownsText = ownsText ?? text == null,
       _focusNode = focusNode ?? FocusNode(debugLabel: 'ChatComposer'),
       _ownsFocus = focusNode == null,
       _fieldScroll = fieldScroll ?? ScrollController(),
       _ownsFieldScroll = fieldScroll == null,
       super(
         ChatComposerState.initial(
           data: ChatComposerStateEntity(
             mode: const ChatComposerMode.idle(),
             emojiIcon: ChatEnterEmojiIconState.smile,
             enabled: enabled,
             busy: false,
           ),
         ),
       );

  final TextEditingController _text;
  final bool _ownsText;
  final FocusNode _focusNode;
  final bool _ownsFocus;
  final ScrollController _fieldScroll;
  final bool _ownsFieldScroll;

  var _disposed = false;

  VoidCallback? _projectRequestKeyboard;
  VoidCallback? _projectHideKeyboard;
  VoidCallback? _projectHideKeyboardRetainingFocus;
  VoidCallback? _projectPrepareKeyboardHandoff;

  /// Text editing controller of the field.
  TextEditingController get text => _text;

  /// Current state of the composer.
  ChatComposerState get state => value;

  /// Data entity payload of the current state.
  ChatComposerStateEntity get data => state.data;

  /// Current mode of the composer.
  ChatComposerMode get mode => data.mode;

  /// Focus node of the field.
  FocusNode get focusNode => _focusNode;

  /// Inner field scroll controller (programmatic jump-to-end after edit).
  ScrollController get fieldScroll => _fieldScroll;

  /// Current emoji icon state of the composer.
  ChatEnterEmojiIconState get emojiIconState => data.emojiIcon;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  @nonVirtual
  @protected
  /// Sets the state of the composer.
  void setState(ChatComposerState state) {
    if (state.data == data) return;
    if (_disposed) return;
    super.value = state;
  }

  // --- Commands -------------------------------------------------------------

  /// Enables or disables composer chrome. Same-value is a silent no-op.
  void setEnabled(bool value) {
    if (data.enabled == value) return;
    setState(
      .processing(
        data: data,
        message: 'Chaning enabled from ${data.enabled} to $value',
      ),
    );
    setState(
      .idle(
        data: data.copyWith(enabled: value),
        message: 'Enabled changed to $value',
      ),
    );
    if (!value) {
      unfocus();
    }
  }

  /// Sets the emoji-button face (host usually via [resolveEmojiIconState]).
  void setEmojiIconState(ChatEnterEmojiIconState state) {
    if (data.emojiIcon == state) return;
    setState(
      .processing(
        data: data,
        message: 'Chaning emoji icon from ${data.emojiIcon} to $state',
      ),
    );
    setState(
      .idle(
        data: data.copyWith(emojiIcon: state),
        message: 'Emoji icon changed to $state',
      ),
    );
  }

  /// Marks an in-flight send/edit. Same-value is a silent no-op.
  void setBusy(bool value) {
    if (data.busy == value) return;
    setState(
      .processing(
        data: data,
        message: 'Chaning busy from ${data.busy} to $value',
      ),
    );
    setState(
      .idle(
        data: data.copyWith(busy: value),
        message: 'Busy changed to $value',
      ),
    );
  }

  /// Enters edit mode. Host MUST write [text] (plain or rich) before this call.
  ///
  /// [id] is opaque host identity; [preview] is the banner body (marker-free).
  /// Schedules field scroll-to-end and [requestKeyboard]. Same-value mode with
  /// identical id/preview still re-requests keyboard. Disabled / disposed → no-op.
  void beginEdit({required Object id, required String preview}) {
    if (!data.enabled) return;
    final next = ChatComposerMode$Editing(id: id, preview: preview);
    if (data.mode != next) {
      setState(
        .processing(
          data: data,
          message: 'Chaning mode from ${data.mode} to $next',
        ),
      );
      setState(
        .idle(
          data: data.copyWith(mode: next),
          message: 'Mode changed to $next',
        ),
      );
    }
    _scrollFieldToEnd();
    requestKeyboard();
  }

  /// Enters reply mode. Does not mutate [text].
  void beginReply({
    required Object id,
    required String title,
    required String subtitle,
  }) {
    if (!data.enabled) return;
    final next = ChatComposerMode.replying(
      id: id,
      title: title,
      subtitle: subtitle,
    );
    if (data.mode == next) return;
    setState(
      .processing(
        data: data,
        message: 'Chaning mode from ${data.mode} to $next',
      ),
    );
    setState(
      .idle(
        data: data.copyWith(mode: next),
        message: 'Mode changed to $next',
      ),
    );
    requestKeyboard();
  }

  /// Returns to idle without clearing [text].
  void cancelMode() {
    if (data.mode.isIdle) return;
    final next = const ChatComposerMode.idle();
    setState(
      .processing(
        data: data,
        message: 'Chaning mode from ${data.mode} to $next',
      ),
    );
    setState(
      .idle(
        data: data.copyWith(mode: next),
        message: 'Mode changed to $next',
      ),
    );
  }

  /// Clears field text and returns to idle.
  void clear() {
    if (_disposed) return;
    _text.value = const TextEditingValue(
      selection: TextSelection.collapsed(offset: 0),
    );
    cancelMode();
  }

  /// Inserts [value] at the caret.
  void insertText(String value) {
    if (_disposed || !data.enabled) return;
    final current = _text.value;
    final start = current.selection.start >= 0
        ? current.selection.start
        : current.text.length;
    final end = current.selection.end >= 0
        ? current.selection.end
        : current.text.length;
    final next = current.text.replaceRange(start, end, value);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  /// Deletes the last grapheme cluster behind the caret.
  void backspace() {
    if (_disposed || !data.enabled) return;
    emojiBackspace(_text);
  }

  /// Programmatic focus + soft IME show (projects when enter view is bound).
  void requestKeyboard() {
    if (_disposed || !data.enabled) return;
    final project = _projectRequestKeyboard;
    if (project != null) {
      project();
      return;
    }
    // Unbound fallback — focus only; soft IME may need a bound enter view.
    _focusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  /// Hides soft IME.
  void hideKeyboard() {
    if (_disposed) return;
    final project = _projectHideKeyboard;
    if (project != null) {
      project();
      return;
    }
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  /// Hides soft IME; keeps caret (keyboard panel open).
  void hideKeyboardRetainingFocus() {
    if (_disposed) return;
    final project = _projectHideKeyboardRetainingFocus;
    if (project != null) {
      project();
      return;
    }
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  /// Arms one focus gain so panel IME-suppress does not hide the soft keyboard.
  void prepareKeyboardHandoff() {
    if (_disposed) return;
    _projectPrepareKeyboardHandoff?.call();
  }

  /// Drops focus — use only when the field should fully resign input.
  void unfocus() {
    if (_disposed) return;
    _focusNode.unfocus();
  }

  /// Programmatic [TextEditingValue] changes do not schedule caret-on-screen —
  /// jump field scroll to the end after layout.
  void scrollFieldToEnd() => _scrollFieldToEnd();

  void _scrollFieldToEnd({int frame = 0}) {
    if (_disposed) return;
    void attempt() {
      if (_disposed) return;
      if (_fieldScroll.hasClients) {
        final max = _fieldScroll.position.maxScrollExtent;
        _fieldScroll.jumpTo(max);
        if (frame < 2) {
          SchedulerBinding.instance.addPostFrameCallback(
            (_) => _scrollFieldToEnd(frame: frame + 1),
          );
        }
        return;
      }
      if (frame < 4) {
        SchedulerBinding.instance.addPostFrameCallback(
          (_) => _scrollFieldToEnd(frame: frame + 1),
        );
      }
    }

    SchedulerBinding.instance.addPostFrameCallback((_) => attempt());
  }

  // --- Enter bind -----------------------------------------------------------

  /// Registers IME / focus projection for the mounted enter view.
  ///
  /// Enter-view-only. Pass `null` handlers on detach. Does not dispose this
  /// controller.
  void bindEnterProjection({
    VoidCallback? onRequestKeyboard,
    VoidCallback? onHideKeyboard,
    VoidCallback? onHideKeyboardRetainingFocus,
    VoidCallback? onPrepareKeyboardHandoff,
  }) {
    if (_disposed) return;
    _projectRequestKeyboard = onRequestKeyboard;
    _projectHideKeyboard = onHideKeyboard;
    _projectHideKeyboardRetainingFocus = onHideKeyboardRetainingFocus;
    _projectPrepareKeyboardHandoff = onPrepareKeyboardHandoff;
  }

  // --- Lifecycle ------------------------------------------------------------

  /// Drops projection binds; disposes owned text/focus/scroll. Idempotent.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _projectRequestKeyboard = null;
    _projectHideKeyboard = null;
    _projectHideKeyboardRetainingFocus = null;
    _projectPrepareKeyboardHandoff = null;
    if (_ownsText) {
      _text.dispose();
    }
    if (_ownsFocus) {
      _focusNode.dispose();
    }
    if (_ownsFieldScroll) {
      _fieldScroll.dispose();
    }
    super.dispose();
  }
}

/// {@template chat_composer_state_entity}
/// Stable chrome fields carried by every [ChatComposerState] variant.
/// {@endtemplate}
@immutable
class ChatComposerStateEntity {
  /// {@macro chat_composer_state_entity}
  const ChatComposerStateEntity({
    required this.mode,
    required this.emojiIcon,
    required this.enabled,
    required this.busy,
  });

  /// The current mode of the composer.
  final ChatComposerMode mode;

  /// The current emoji icon state of the composer.
  final ChatEnterEmojiIconState emojiIcon;

  /// Whether the composer is busy.
  final bool busy;

  /// Whether the composer is enabled.
  final bool enabled;

  /// Copies the entity with the given properties.
  ChatComposerStateEntity copyWith({
    ChatComposerMode? mode,
    ChatEnterEmojiIconState? emojiIcon,
    bool? busy,
    bool? enabled,
  }) => ChatComposerStateEntity(
    mode: mode ?? this.mode,
    emojiIcon: emojiIcon ?? this.emojiIcon,
    busy: busy ?? this.busy,
    enabled: enabled ?? this.enabled,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatComposerStateEntity &&
          mode == other.mode &&
          emojiIcon == other.emojiIcon &&
          busy == other.busy &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(mode, emojiIcon, busy, enabled);
}

/// {@template chat_composer_state}
/// ChatComposerState.
/// {@endtemplate}
sealed class ChatComposerState extends _$ChatComposerStateBase {
  /// {@macro chat_composer_state}
  const ChatComposerState({
    required super.data,
    required super.message,
    super.error,
  });

  /// Idle
  /// {@macro chat_composer_state}
  const factory ChatComposerState.idle({
    required ChatComposerStateEntity data,
    String message,
    Object? error,
  }) = ChatComposerState$Idle;

  /// Processing
  /// {@macro chat_composer_state}
  const factory ChatComposerState.processing({
    required ChatComposerStateEntity data,
    String message,
    Object? error,
  }) = ChatComposerState$Processing;

  /// Failed
  /// {@macro chat_composer_state}
  const factory ChatComposerState.failed({
    required ChatComposerStateEntity data,
    String message,
    Object? error,
  }) = ChatComposerState$Failed;

  /// Initial
  /// {@macro chat_composer_state}
  factory ChatComposerState.initial({
    required ChatComposerStateEntity data,
    String? message,
    Object? error,
  }) => ChatComposerState$Idle(
    data: data,
    message: message ?? 'Initial',
    error: error,
  );
}

/// {@template chat_composer_state_idle}
/// Idle state of the composer.
/// {@endtemplate}
final class ChatComposerState$Idle extends ChatComposerState {
  /// {@macro chat_composer_state_idle}
  const ChatComposerState$Idle({
    required super.data,
    super.message = 'Idle',
    super.error,
  });

  @override
  String get type => 'idle';
}

/// {@template chat_composer_state_processing}
/// Processing state of the composer.
/// {@endtemplate}
final class ChatComposerState$Processing extends ChatComposerState {
  /// {@macro chat_composer_state_processing}
  const ChatComposerState$Processing({
    required super.data,
    super.message = 'Processing',
    super.error,
  });

  @override
  String get type => 'processing';
}

/// {@template chat_composer_state_failed}
/// Failed state of the composer.
/// {@endtemplate}
final class ChatComposerState$Failed extends ChatComposerState {
  /// {@macro chat_composer_state_failed}
  const ChatComposerState$Failed({
    required super.data,
    super.message = 'Failed',
    super.error,
  });

  @override
  String get type => 'failed';
}

/// Pattern matching for [ChatComposerState].
typedef ChatComposerStateMatch<R, S extends ChatComposerState> =
    R Function(S element);

@immutable
abstract base class _$ChatComposerStateBase {
  const _$ChatComposerStateBase({
    required this.data,
    required this.message,
    this.error,
  });

  /// Type alias for [ChatComposerState].
  abstract final String type;

  /// Data entity payload.
  @nonVirtual
  final ChatComposerStateEntity data;

  /// Message or description.
  @nonVirtual
  final String message;

  /// Error object.
  @nonVirtual
  final Object? error;

  /// Check if is Idle.
  bool get isIdle => this is ChatComposerState$Idle;

  /// Check if is Processing.
  bool get isProcessing => this is ChatComposerState$Processing;

  /// Check if is Failed.
  bool get isFailed => this is ChatComposerState$Failed;

  /// Pattern matching for [ChatComposerState].
  R map<R>({
    required ChatComposerStateMatch<R, ChatComposerState$Idle> idle,
    required ChatComposerStateMatch<R, ChatComposerState$Processing> processing,
    required ChatComposerStateMatch<R, ChatComposerState$Failed> failed,
  }) => switch (this) {
    ChatComposerState$Idle s => idle(s),
    ChatComposerState$Processing s => processing(s),
    ChatComposerState$Failed s => failed(s),
    _ => throw AssertionError(),
  };

  /// Pattern matching for [ChatComposerState].
  R maybeMap<R>({
    required R Function() orElse,
    ChatComposerStateMatch<R, ChatComposerState$Idle>? idle,
    ChatComposerStateMatch<R, ChatComposerState$Processing>? processing,
    ChatComposerStateMatch<R, ChatComposerState$Failed>? failed,
  }) => map<R>(
    idle: idle ?? (_) => orElse(),
    processing: processing ?? (_) => orElse(),
    failed: failed ?? (_) => orElse(),
  );

  /// Pattern matching for [ChatComposerState].
  R? mapOrNull<R>({
    ChatComposerStateMatch<R, ChatComposerState$Idle>? idle,
    ChatComposerStateMatch<R, ChatComposerState$Processing>? processing,
    ChatComposerStateMatch<R, ChatComposerState$Failed>? failed,
  }) => map<R?>(
    idle: idle ?? (_) => null,
    processing: processing ?? (_) => null,
    failed: failed ?? (_) => null,
  );

  @override
  int get hashCode => Object.hash(type, data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _$ChatComposerStateBase &&
          type == other.type &&
          data == other.data);

  @override
  String toString() => 'ChatComposerState.$type{message: $message}';
}
