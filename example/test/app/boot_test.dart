/// What a failed boot shows, and that a good one is unchanged.
library;

import 'package:chat_scroll_view_example/src/app/boot.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_services.dart';

void main() {
  testWidgets('a failed boot runs the failure screen with the error, not a '
      'blank app', (tester) async {
    final ran = <Widget>[];

    await bootApp(
      createServices: () async => throw StateError('no catalogue'),
      appOf: (_) => throw StateError('not built'),
      run: ran.add,
    );

    expect(ran, hasLength(1));
    await tester.pumpWidget(ran.single);
    expect(find.text('The app could not start'), findsOneWidget);
    expect(find.textContaining('no catalogue'), findsOneWidget);
  });

  testWidgets('a good boot runs the app over the services', (tester) async {
    final services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    final ran = <Widget>[];
    const app = SizedBox();

    await bootApp(
      createServices: () async => services,
      appOf: (given) {
        expect(given, same(services));
        return app;
      },
      run: ran.add,
    );

    expect(ran, [same(app)]);
  });
}
