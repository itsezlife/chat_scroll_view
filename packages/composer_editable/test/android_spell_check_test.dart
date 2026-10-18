import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A spell check service that finds nothing misspelled.
final class _FlawlessSpellCheck implements SpellCheckService {
  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async => const <SuggestionSpan>[];
}

void main() {
  final enabled = SpellCheckConfiguration(
    spellCheckService: _FlawlessSpellCheck(),
  );

  group('inferAndroidSpellCheckConfiguration', () {
    test('keeps a disabled or missing configuration disabled', () {
      expect(
        ExtendedTextField.inferAndroidSpellCheckConfiguration(null),
        const SpellCheckConfiguration.disabled(),
      );
      expect(
        ExtendedTextField.inferAndroidSpellCheckConfiguration(
          const SpellCheckConfiguration.disabled(),
        ),
        const SpellCheckConfiguration.disabled(),
      );
    });

    test(
      'fills the Material defaults of an enabled one without a TypeError',
      () {
        final inferred = ExtendedTextField.inferAndroidSpellCheckConfiguration(
          enabled,
        );

        expect(inferred.spellCheckEnabled, isTrue);
        expect(
          inferred.misspelledTextStyle,
          ExtendedTextField.materialMisspelledTextStyle,
        );
        expect(inferred.spellCheckSuggestionsToolbarBuilder, isNotNull);
      },
    );

    test('keeps a builder the host supplied', () {
      Widget hostBuilder(BuildContext context, EditableTextState state) =>
          const SizedBox();
      final inferred = ExtendedTextField.inferAndroidSpellCheckConfiguration(
        SpellCheckConfiguration(
          spellCheckService: _FlawlessSpellCheck(),
          spellCheckSuggestionsToolbarBuilder: hostBuilder,
        ),
      );

      expect(inferred.spellCheckSuggestionsToolbarBuilder, hostBuilder);
    });
  });

  group('on Android', () {
    Future<ExtendedEditableTextState> pumpField(
      WidgetTester tester,
      TextEditingController controller,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExtendedTextField(
              controller: controller,
              spellCheckConfiguration: enabled,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.state<ExtendedEditableTextState>(
        find.byType(ExtendedEditableText),
      );
    }

    testWidgets('a field with spell check enabled builds and edits', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'alpha beta');
      addTearDown(controller.dispose);
      try {
        final state = await pumpField(tester, controller);

        expect(tester.takeException(), isNull);
        expect(state.spellCheckEnabled, isTrue);

        controller.text = 'alpha betta';
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('the default toolbar builder takes the extended state', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'alpha beta');
      addTearDown(controller.dispose);
      try {
        final state = await pumpField(tester, controller);
        final builder =
            ExtendedTextField.inferAndroidSpellCheckConfiguration(
                  enabled,
                ).spellCheckSuggestionsToolbarBuilder!
                as Function;

        // The editable calls the builder with its own state, which is not an
        // [EditableTextState]; that call is what threw.
        final toolbar = builder(state.context, state);

        expect(toolbar, isA<Widget>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('suggestions stay off: a tap on a word shows no toolbar', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'alpha beta');
      addTearDown(controller.dispose);
      try {
        final state = await pumpField(tester, controller);

        await tester.tap(find.byType(ExtendedTextField));
        await tester.pumpAndSettle();

        expect(state.showSpellCheckSuggestionsToolbar(), isFalse);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
