import 'package:chat_capabilities/src/capability/capability.dart';
import 'package:chat_capabilities/src/chat_capabilities.dart';
import 'package:chat_capabilities/src/group/chat_limits.dart';
import 'package:chat_capabilities/src/group/chat_protection.dart';
import 'package:chat_capabilities/src/group/sending_capabilities.dart';
import 'package:chat_capabilities/src/group/slow_mode.dart';
import 'package:chat_capabilities/src/group/write_access.dart';
import 'package:listen/listen.dart';

/// A settable chat capabilities source, standing in for the host's
/// listenable in tests of consumers.
///
/// Unlike a `ValueNotifier`, it notifies on every [set], equal values
/// included, the way a host that pushes each backend update does; a
/// consumer's own deduplication (`select`) is what a test then observes.
final class FakeChatCapabilitiesSource extends ChangeNotifier
    implements ValueListenable<ChatCapabilities> {
  /// A source holding [initial], everything allowed by default.
  FakeChatCapabilitiesSource([
    ChatCapabilities initial = const ChatCapabilities(),
  ]) : _value = initial;

  ChatCapabilities _value;

  @override
  ChatCapabilities get value => _value;

  /// Whether anything listens, so a test can check that a consumer
  /// unsubscribed.
  bool get isListenedTo => hasListeners;

  /// Replaces the value and notifies.
  void set(ChatCapabilities value) {
    _value = value;
    notifyListeners();
  }

  /// Replaces the given groups of the value and notifies.
  void update({
    SendingCapabilities? sending,
    WriteAccess? writeAccess,
    SlowMode? slowMode,
    ChatProtection? protection,
    ChatLimits? limits,
    Map<String, Capability>? custom,
  }) => set(
    _value.copyWith(
      sending: sending,
      writeAccess: writeAccess,
      slowMode: slowMode,
      protection: protection,
      limits: limits,
      custom: custom,
    ),
  );
}
