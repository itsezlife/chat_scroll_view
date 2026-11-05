import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Divergence L: the text processing actions are queried once per app run,
/// not by every field that mounts.
void main() {
  late int queries;

  setUp(() {
    queries = 0;
    ExtendedEditableTextState.debugResetProcessTextActions();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.processText, (call) async {
          if (call.method == 'ProcessText.queryTextActions') queries++;
          return <String, String>{'translate': 'Translate'};
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.processText, null);
    ExtendedEditableTextState.debugResetProcessTextActions();
  });

  Widget field(Key key) => MaterialApp(
    home: Scaffold(
      body: ExtendedTextField(key: key, controller: TextEditingController()),
    ),
  );

  testWidgets('a field mounted again asks no second time', (tester) async {
    await tester.pumpWidget(field(const Key('first')));
    await tester.pump();
    expect(queries, 1);

    // A new key mounts a new field, as the composer's does after a message
    // selection ends.
    await tester.pumpWidget(field(const Key('second')));
    await tester.pump();
    expect(queries, 1);
  });

  testWidgets('a field after a prefetch asks no more', (tester) async {
    ExtendedEditableTextState.prefetchProcessTextActions();
    ExtendedEditableTextState.prefetchProcessTextActions();
    expect(queries, 1);

    await tester.pumpWidget(field(const Key('first')));
    await tester.pump();
    expect(queries, 1);
  });
}
