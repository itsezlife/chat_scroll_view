import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActionDescriptor', () {
    test('defaults to an enabled, visible, trailing, non-primary action', () {
      const action = ActionDescriptor(
        id: 'attach',
        icon: ChromeIconId.attach,
        semanticLabel: 'Attach',
      );

      expect(action.placement, ActionPlacement.trailing);
      expect(action.enabled, isTrue);
      expect(action.visible, isTrue);
      expect(action.primary, isFalse);
      expect(action.onTap, isNull);
    });

    test('has no wrapper and is not active by default', () {
      const action = ActionDescriptor(
        id: 'panel',
        icon: ChromeIconId.emoji,
        semanticLabel: 'Panel',
      );

      expect(action.wrap, isNull);
      expect(action.active, isFalse);
    });

    test('copyWith carries the wrapper and the active flag', () {
      Widget wrap(BuildContext context, Widget button) => button;
      final action = ActionDescriptor(
        id: 'panel',
        icon: ChromeIconId.emoji,
        semanticLabel: 'Panel',
        wrap: wrap,
        active: true,
      );

      expect(action.copyWith(enabled: false).wrap, same(action.wrap));
      expect(action.copyWith(enabled: false).active, isTrue);
      expect(action.copyWith(active: false).active, isFalse);
    });

    test('is usable only when enabled, visible and given a handler', () {
      void tap() {}
      final usable = ActionDescriptor(
        id: 'a',
        icon: ChromeIconId.send,
        semanticLabel: 'Send',
        onTap: tap,
      );

      expect(usable.isTappable, isTrue);
      expect(usable.copyWith(enabled: false).isTappable, isFalse);
      expect(usable.copyWith(visible: false).isTappable, isFalse);
      expect(
        const ActionDescriptor(
          id: 'a',
          icon: ChromeIconId.send,
          semanticLabel: 'Send',
        ).isTappable,
        isFalse,
      );
    });

    test('rejects an empty semantic label', () {
      expect(
        () => ActionDescriptor(
          id: 'a',
          icon: ChromeIconId.send,
          semanticLabel: '',
        ),
        throwsAssertionError,
      );
    });

    test('rejects an empty id', () {
      expect(
        () => ActionDescriptor(
          id: '',
          icon: ChromeIconId.send,
          semanticLabel: 'Send',
        ),
        throwsAssertionError,
      );
    });
  });

  group('ComposerSpec', () {
    test('defaults to the text panel, no header, no actions, enabled', () {
      final spec = ComposerSpec();

      expect(spec.header, isNull);
      expect(spec.panel, ComposerPanelId.text);
      expect(spec.actions, isEmpty);
      expect(spec.enabled, isTrue);
      expect(spec.busy, isFalse);
    });

    test('rejects two actions with the same id', () {
      expect(
        () => ComposerSpec(
          actions: const [
            ActionDescriptor(
              id: 'x',
              icon: ChromeIconId.send,
              semanticLabel: 'a',
            ),
            ActionDescriptor(
              id: 'x',
              icon: ChromeIconId.attach,
              semanticLabel: 'b',
            ),
          ],
        ),
        throwsAssertionError,
      );
    });

    test('lists the actions of a placement in spec order', () {
      const lead = ActionDescriptor(
        id: 'lead',
        icon: ChromeIconId.emoji,
        semanticLabel: 'Emoji',
        placement: ActionPlacement.leading,
      );
      const a = ActionDescriptor(
        id: 'a',
        icon: ChromeIconId.attach,
        semanticLabel: 'A',
      );
      const b = ActionDescriptor(
        id: 'b',
        icon: ChromeIconId.voice,
        semanticLabel: 'B',
        visible: false,
      );
      final spec = ComposerSpec(actions: const [a, lead, b]);

      expect(spec.visibleActions(ActionPlacement.leading), [lead]);
      expect(spec.visibleActions(ActionPlacement.trailing), [a]);
    });
  });
}
