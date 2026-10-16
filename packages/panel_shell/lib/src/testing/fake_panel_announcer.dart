import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/input/panel_announcer.dart';

/// A [PanelAnnouncer] that records what was announced instead of speaking.
final class FakePanelAnnouncer implements PanelAnnouncer {
  /// The messages announced so far, oldest first.
  final List<String> messages = [];

  @override
  void announce(BuildContext context, String message) => messages.add(message);
}
