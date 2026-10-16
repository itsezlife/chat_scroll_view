import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

InlineContentRef _ref(String key, String alt) =>
    InlineContentRef(key: ContentKey.document(key), alternativeText: alt);

void main() {
  late FakeAssetProducer producer;
  late AssetCacheScope scope;
  late ComposerController controller;

  setUp(() {
    producer = FakeAssetProducer();
    scope = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
    controller = ComposerController(
      text: ComposerTextController(
        inlineContentBuilder: ContentViewSpans.builder(scope: scope),
      ),
    );
  });
  tearDown(() {
    controller.dispose();
    scope.dispose();
  });

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    composerHarness(ComposerView(controller: controller, spec: ComposerSpec())),
  );

  testWidgets('draws a reference through ContentView at its alt text length', (
    tester,
  ) async {
    await show(tester);

    // Alt texts of one unit, a surrogate pair and a ZWJ sequence: the span
    // must lay out as exactly that many code units, which the text
    // controller asserts while painting.
    for (final alt in ['a', '\u{1F642}', '\u{1F468}‍\u{1F469}‍\u{1F467}']) {
      controller.insertContent(_ref('k${alt.length}', alt));
    }
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ContentView), findsNWidgets(3));
    expect(controller.richText.entities, hasLength(3));
  });

  testWidgets(
    'attaches each reference to the scope and drops the view on removal',
    (tester) async {
      await show(tester);

      controller.insertContent(_ref('smile', '\u{1F642}'));
      await tester.pump();
      await tester.pump();
      expect(producer.attempts, isNotEmpty);

      controller.clear();
      await tester.pump();
      await tester.pump();

      expect(find.byType(ContentView), findsNothing);
    },
  );

  testWidgets('labels the content with its alternative text', (tester) async {
    await show(tester);

    controller.insertContent(_ref('smile', '\u{1F642}'));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<ContentView>(find.byType(ContentView)).semanticLabel,
      '\u{1F642}',
    );
  });
}
