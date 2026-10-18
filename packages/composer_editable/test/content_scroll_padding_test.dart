import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The content inset is opt-in, and a placeholder never makes it an error.
void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    EdgeInsets? inset,
    required InputDecoration decoration,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 320,
            child: ExtendedTextField(
              maxLines: 3,
              contentScrollPadding: inset ?? EdgeInsets.zero,
              decoration: decoration,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('is off by default', (tester) async {
    await pumpField(
      tester,
      decoration: const InputDecoration.collapsed(hintText: 'Message'),
    );

    expect(
      tester
          .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
          .renderEditable
          .contentScrollPadding,
      EdgeInsets.zero,
    );
  });

  testWidgets('with hintText builds without an error', (tester) async {
    await pumpField(
      tester,
      inset: const EdgeInsets.symmetric(vertical: 8),
      decoration: const InputDecoration.collapsed(hintText: 'Message'),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('both hint forms follow the inset', (
    tester,
  ) async {
    const inset = 8.0;
    await pumpField(
      tester,
      decoration: const InputDecoration.collapsed(
        hintText: null,
        hint: Text('Message'),
      ),
    );
    final flush = tester.getTopLeft(find.text('Message')).dy;

    await pumpField(
      tester,
      decoration: const InputDecoration.collapsed(hintText: 'Message'),
    );
    final flushText = tester.getTopLeft(find.text('Message')).dy;

    await pumpField(
      tester,
      inset: const EdgeInsets.symmetric(vertical: inset),
      decoration: const InputDecoration.collapsed(
        hintText: null,
        hint: Text('Message'),
      ),
    );
    final insetHint = tester.getTopLeft(find.text('Message')).dy;

    await pumpField(
      tester,
      inset: const EdgeInsets.symmetric(vertical: inset),
      decoration: const InputDecoration.collapsed(hintText: 'Message'),
    );
    final insetHintText = tester.getTopLeft(find.text('Message')).dy;

    expect(insetHint - flush, inset);
    expect(insetHintText - flushText, inset);
  });
}
