/// Where the composer puts its actions for each way of reaching the panel.
///
/// **Seam:** [buildChatComposerSpec], observed through the placement of each
/// action in the spec it returns.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter_test/flutter_test.dart';

ComposerSpec _spec({required ActionPlacement panelPlacement}) =>
    buildChatComposerSpec(
      strings: ChromeStringsPresets.english,
      editing: null,
      hasText: false,
      busy: false,
      panelReplacesKeyboard: false,
      panelDocked: false,
      panelPlacement: panelPlacement,
      wrapPanelToggle: null,
      pageIcon: ChromeIconId.emoji,
      onTogglePanel: () {},
      onSubmit: () {},
      onAttach: () {},
      onVoice: () {},
      onCancelEdit: () {},
    );

ActionPlacement _placementOf(ComposerSpec spec, String id) =>
    spec.actions.firstWhere((action) => action.id == id).placement;

void main() {
  group('where the panel is a popup or a dock (a desktop)', () {
    final spec = _spec(panelPlacement: ActionPlacement.trailing);

    test('attach is at the start edge, before the field', () {
      expect(
        _placementOf(spec, ChatComposerActions.attach),
        ActionPlacement.leading,
      );
    });

    test('the panel toggle and the primary action are at the end', () {
      expect(
        _placementOf(spec, ChatComposerActions.panel),
        ActionPlacement.trailing,
      );
      expect(
        _placementOf(spec, ChatComposerActions.primary),
        ActionPlacement.trailing,
      );
    });
  });

  group('where the panel replaces the keyboard (a phone)', () {
    final spec = _spec(panelPlacement: ActionPlacement.leading);

    test('the panel toggle is first and attach stays at the end', () {
      expect(
        _placementOf(spec, ChatComposerActions.panel),
        ActionPlacement.leading,
      );
      expect(
        _placementOf(spec, ChatComposerActions.attach),
        ActionPlacement.trailing,
      );
    });
  });
}
