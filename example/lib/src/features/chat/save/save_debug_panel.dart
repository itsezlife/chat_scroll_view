import 'dart:async';

import 'package:chat_scroll_view_example/src/features/chat/save/save_debug_actions.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:mpx_library/mpx_library.dart';

/// The save debug panel (debug builds): one button per destination that
/// saves the bundled demo photo there through the app's saver, with each
/// destination's last outcome beside it. The saver's own events are in the
/// journal (category `save`).
///
/// Shows no user content: the item is the example's own photo, and the
/// outcomes are states and failure reasons.
class SaveDebugPanel extends StatelessWidget {
  /// The panel over [actions].
  const SaveDebugPanel({required this.actions, super.key});

  /// The actions the buttons call.
  final SaveDebugActions actions;

  /// Key of the button that saves to [destination].
  static ValueKey<String> saveKey(SaveDestination destination) =>
      ValueKey('save-debug-${destination.name}');

  /// Key of the chat chrome's button that opens the panel.
  static const ValueKey<String> openKey = ValueKey('save-debug-open');

  /// The panel as a route, under a chrome text root.
  static Route<void> route({required SaveDebugActions actions}) =>
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'save/debug'),
        builder: (_) => ChromeTextRoot(child: SaveDebugPanel(actions: actions)),
      );

  static String _label(SaveDestination destination) => switch (destination) {
    SaveDestination$Gallery() => 'Save to the gallery',
    SaveDestination$Downloads() => 'Save to Downloads',
    SaveDestination$Ask() => 'Save as…',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = ChromeTypography.of(context).copyWith(color: colors.onSurface);
    final small = base.copyWith(fontSize: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Save debug',
          style: base.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
      body: ValueListenableBuilder<Map<String, String>>(
        valueListenable: actions.outcomes,
        builder: (context, outcomes, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text('Saves a bundled photo through the app saver.', style: small),
            const SizedBox(height: 8),
            for (final destination in SaveDebugActions.destinations)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    FilledButton.tonal(
                      key: saveKey(destination),
                      onPressed: () =>
                          unawaited(actions.saveDemoTo(destination)),
                      child: Text(_label(destination), style: base),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        outcomes[destination.name] ?? '-',
                        style: small,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
