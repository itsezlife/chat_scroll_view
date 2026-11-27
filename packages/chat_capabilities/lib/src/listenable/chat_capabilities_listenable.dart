import 'package:chat_capabilities/src/chat_capabilities.dart';
import 'package:chat_capabilities/src/diagnostics/capabilities_op.dart';
import 'package:chat_capabilities/src/group/write_access.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';

/// How consumers read a chat's capabilities: one group at a time, and with
/// the chat's diagnostics events.
extension ChatCapabilitiesListenable on ValueListenable<ChatCapabilities> {
  /// A listenable of one group, chosen by [group], that notifies only when
  /// that group changes by `==`.
  ///
  /// ```dart
  /// final sending = capabilities.select((c) => c.sending);
  /// ```
  ///
  /// A slow mode tick changes `slowMode` only, so a consumer of `sending`
  /// does not rebuild. The selection subscribes to this listenable when its
  /// first listener arrives and unsubscribes when its last one leaves, so a
  /// selection nobody listens to holds no subscription and needs no
  /// disposal. Without listeners its value reads through to the current
  /// group.
  ValueListenable<G> select<G>(
    G Function(ChatCapabilities capabilities) group,
  ) => _GroupSelection(this, group);

  /// This listenable, passed through, reporting the chat's `capabilities`
  /// diagnostics events under [chatId].
  ///
  /// The host builds one per chat around its own listenable and passes it to
  /// the consumers. Each distinct value it sees reports `valueChanged` with
  /// the changed group names, then `invalidValue` for each rule the value
  /// breaks ([ChatCapabilities.brokenRules]) before its listeners hear of
  /// it; debug builds then assert. Like [select], it subscribes only while
  /// listened to; a value that arrives meanwhile is reported when the next
  /// listener attaches.
  ValueListenable<ChatCapabilities> withDiagnostics({required String chatId}) =>
      _ReportedCapabilities(this, ChatCorrelation(chatId: chatId));
}

/// A derived value of [ChatCapabilities] that notifies only when it changes,
/// subscribed to its source only while it has listeners.
///
/// Built by hand on [ChangeNotifier] rather than as a [ValueNotifier] fed by
/// a permanent source listener: the permanent listener would keep every
/// selection a consumer ever made alive as long as the source, a leak no
/// consumer could end without a dispose call it is never asked to make.
abstract base class _LazySelection<T> extends ChangeNotifier
    implements ValueListenable<T> {
  _LazySelection(this._source);

  final ValueListenable<ChatCapabilities> _source;
  bool _attached = false;
  late T _current;

  /// The derived value of [capabilities].
  T read(ChatCapabilities capabilities);

  /// Called once subscribed, with the source's current derived value.
  void didAttach(T value) {}

  /// Called with each distinct derived value while subscribed; notifies.
  void changed(T previous, T next) => notifyListeners();

  @override
  T get value => _attached ? _current : read(_source.value);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_attached) return;
    _current = read(_source.value);
    _source.addListener(_onSource);
    _attached = true;
    didAttach(_current);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    // During a notification the removal is deferred and hasListeners stays
    // true; [_onSource] checks again once the notification ends.
    _detachIfUnheard();
  }

  @override
  void dispose() {
    if (_attached) _detach();
    super.dispose();
  }

  void _onSource() {
    final next = read(_source.value);
    if (next == _current) return;
    final previous = _current;
    _current = next;
    try {
      changed(previous, next);
    } finally {
      _detachIfUnheard();
    }
  }

  void _detachIfUnheard() {
    if (_attached && !hasListeners) _detach();
  }

  void _detach() {
    _source.removeListener(_onSource);
    _attached = false;
  }
}

final class _GroupSelection<G> extends _LazySelection<G> {
  _GroupSelection(super.source, this._group);

  final G Function(ChatCapabilities capabilities) _group;

  @override
  G read(ChatCapabilities capabilities) => _group(capabilities);
}

final class _ReportedCapabilities extends _LazySelection<ChatCapabilities> {
  _ReportedCapabilities(super.source, this._correlation);

  final ChatCorrelation _correlation;

  /// The last value reported, kept across detaches so a value that arrived
  /// while nobody listened is reported once, on the next attach.
  ChatCapabilities? _reported;

  @override
  ChatCapabilities read(ChatCapabilities capabilities) => capabilities;

  @override
  void didAttach(ChatCapabilities value) {
    if (value == _reported) return;
    final broken = _report(_reported, value);
    _assertValid(value, broken);
  }

  @override
  void changed(ChatCapabilities previous, ChatCapabilities next) {
    final broken = _report(previous, next);
    notifyListeners();
    // After the listeners, so a debug build still delivers the value it
    // complains about and the events are already out.
    _assertValid(next, broken);
  }

  List<CapabilitiesRule> _report(
    ChatCapabilities? previous,
    ChatCapabilities next,
  ) {
    _reported = next;
    final diagnostics = ChatDiagnostics.current;
    if (previous != null) {
      diagnostics.emit(
        ChatEventLevel.debug,
        ChatEventCategory.capabilities,
        CapabilitiesOp.valueChanged,
        correlation: _correlation,
        fields: () => _changeFields(previous, next),
      );
    }
    // Checked in every build: the event is the release builds' only report.
    final broken = next.brokenRules;
    for (final rule in broken) {
      diagnostics.emit(
        ChatEventLevel.warning,
        ChatEventCategory.capabilities,
        CapabilitiesOp.invalidValue,
        correlation: _correlation,
        fields: () => {'rule': rule},
      );
    }
    return broken;
  }

  static void _assertValid(
    ChatCapabilities value,
    List<CapabilitiesRule> broken,
  ) {
    assert(
      broken.isEmpty,
      'The chat capabilities break ${broken.map((r) => r.name).join(', ')}: '
      'a host resolves its rights into a value that keeps every rule of '
      'ChatCapabilities.brokenRules. Value: $value',
    );
  }

  static Map<String, Object> _changeFields(
    ChatCapabilities previous,
    ChatCapabilities next,
  ) {
    final protection = next.protection;
    final protected = [
      if (!protection.copy) 'copy',
      if (!protection.forward) 'forward',
      if (!protection.save) 'save',
      if (protection.captureBlocked) 'captureBlocked',
    ];
    return {
      'groups': [
        if (previous.sending != next.sending) 'sending',
        if (previous.writeAccess != next.writeAccess) 'writeAccess',
        if (previous.slowMode != next.slowMode) 'slowMode',
        if (previous.protection != next.protection) 'protection',
        if (previous.limits != next.limits) 'limits',
        if (ChatCapabilities(custom: previous.custom) !=
            ChatCapabilities(custom: next.custom))
          'custom',
      ].join(','),
      'writeAccess': _formName(next.writeAccess),
      'slowModeActive': next.slowMode.isActive,
      'protected': protected.isEmpty ? 'none' : protected.join(','),
    };
  }

  /// The form alone: a reason or tag would make the field host-sized.
  static String _formName(WriteAccess access) => switch (access) {
    WriteAccess$CanWrite() => 'canWrite',
    WriteAccess$ReadOnly() => 'readOnly',
    WriteAccess$Join() => 'join',
    WriteAccess$RequestToJoin() => 'requestToJoin',
    WriteAccess$Restricted() => 'restricted',
    WriteAccess$Custom() => 'custom',
  };
}
