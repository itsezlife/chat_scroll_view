import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view_example/src/common/widgets/listen_value_builder.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/capabilities_switcher.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';

/// The debug switcher: a sheet of the chat's rights, each flipped live
/// through a [CapabilitiesSwitcher].
///
/// Debug builds open it from the chat's top chrome. Its rows follow the
/// chat's value, so a change made elsewhere (a send starting slow mode's
/// wait, a lifted ban) shows here too.
class CapabilitiesSwitcherSheet extends StatelessWidget {
  /// The rows of [switcher]'s chat.
  const CapabilitiesSwitcherSheet({required this.switcher, super.key});

  /// What the rows flip.
  final CapabilitiesSwitcher switcher;

  /// Shows the sheet over [context]'s navigator, under a chrome text root.
  static Future<void> show(
    BuildContext context, {
    required CapabilitiesSwitcher switcher,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        ChromeTextRoot(child: CapabilitiesSwitcherSheet(switcher: switcher)),
  );

  /// Key of [row]'s switch, for a test to tap.
  static ValueKey<String> toggleKey(CapabilityToggle row) =>
      ValueKey<String>('capability-toggle-${row.name}');

  /// Key of [choice]'s chip.
  static ValueKey<String> choiceKey(WriteAccessChoice choice) =>
      ValueKey<String>('capability-write-${choice.name}');

  static const List<(String, List<CapabilityToggle>)> _sections = [
    (
      'Sending',
      [
        CapabilityToggle.text,
        CapabilityToggle.photo,
        CapabilityToggle.video,
        CapabilityToggle.animation,
        CapabilityToggle.file,
        CapabilityToggle.audio,
        CapabilityToggle.voice,
        CapabilityToggle.roundVideo,
        CapabilityToggle.stickers,
        CapabilityToggle.linkPreviews,
      ],
    ),
    (
      'Slow mode',
      [CapabilityToggle.slowMode, CapabilityToggle.slowModePending],
    ),
    (
      'Protection',
      [
        CapabilityToggle.copyProtected,
        CapabilityToggle.forwardProtected,
        CapabilityToggle.saveProtected,
        CapabilityToggle.captureBlocked,
      ],
    ),
    ('Limits', [CapabilityToggle.tightLimits]),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = ChromeTypography.of(context).copyWith(color: colors.onSurface);
    final heading = base.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: colors.primary,
    );
    Widget header(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: heading),
    );
    return ListenValueBuilder<ChatCapabilities>(
      listenable: switcher.host.capabilities,
      builder: (context, value) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 16,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Chat rights',
                style: base.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            header('Write access'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in WriteAccessChoice.values)
                    ChoiceChip(
                      key: choiceKey(choice),
                      label: Text(choice.label, style: base),
                      selected:
                          WriteAccessChoice.of(value.writeAccess) == choice,
                      onSelected: (_) => switcher.choose(choice),
                    ),
                ],
              ),
            ),
            for (final (title, rows) in _sections) ...[
              header(title),
              for (final row in rows)
                _ToggleRow(
                  key: toggleKey(row),
                  label: row.label,
                  style: base,
                  on: row.isOn(value),
                  enabled: row.enabledIn(value),
                  onChanged: () => switcher.toggle(row),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One right: its label and a switch, the whole row a tap target.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.style,
    required this.on,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String label;
  final TextStyle style;
  final bool on;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: enabled ? onChanged : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: enabled
                    ? style
                    : style.copyWith(color: Theme.of(context).disabledColor),
              ),
            ),
            Switch(value: on, onChanged: enabled ? (_) => onChanged() : null),
          ],
        ),
      ),
    ),
  );
}
