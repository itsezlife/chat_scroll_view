/// The content preview of a custom emoji on the emoji page, through the
/// policy the scaffold asks.
///
/// **Seam:** [EmojiPagePolicy] given a [ContentPreviewController], its long
/// press begun the way the scaffold begins it under an [Overlay], observed
/// through the session, the menu's texts and the requests the
/// [FakePanelPageHost] received.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/testing.dart';

import '../emoji/emoji_fixtures.dart' as fixtures;

final _recentsSection = CollectionId.recent.toString();
const _recents = Collection(id: CollectionId.recent);

CatalogLeafHit _custom(String id, {String? section}) => CatalogLeafHit(
  sectionId: section ?? _recentsSection,
  index: 0,
  leaf: CatalogLeaf(
    key: ContentKey.document(id),
    semanticKind: SemanticKind.customEmoji,
  ),
);

void main() {
  late FakePanelPageHost host;
  late FakePreferenceStore preferences;
  late AssetCacheScope assets;
  late ContentPreviewController previews;
  late EmojiPagePolicy policy;

  setUp(() {
    host = FakePanelPageHost(pageId: 'emoji');
    preferences = FakePreferenceStore();
    assets = PageAssets.createScope();
    previews = ContentPreviewController();
    policy = EmojiPagePolicy(
      host: host,
      entryOf: fixtures.entryOf,
      preferences: preferences,
      assets: assets,
      previews: previews,
    );
    addTearDown(() {
      previews.dispose();
      assets.dispose();
      host.dispose();
      preferences.dispose();
    });
  });

  Future<CatalogLongPressSession?> longPress(
    WidgetTester tester,
    CatalogLeafHit hit,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(800, 600),
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (c) {
                context = c;
                return const SizedBox.expand();
              },
            ),
          ],
        ),
      ),
    );
    final session = policy.beginLongPress(
      context,
      hit,
      _recents,
      const LongPressStartDetails(),
      kind: PointerDeviceKind.touch,
      cellBounds: const Rect.fromLTWH(0, 0, 40, 40),
      viewportBounds: const Rect.fromLTWH(0, 0, 360, 480),
    );
    await tester.pump();
    await tester.pump(ContentPreviewSession.showDuration);
    return session;
  }

  test('a custom emoji is held 200 ms; a unicode one keeps its own rule', () {
    expect(policy.hasLongPress(_custom('e', section: 's'), _recents), isTrue);
    expect(
      policy.longPressDelayOf(_custom('e'), _recents, PointerDeviceKind.touch),
      ContentPreviewSession.touchHoldDelay,
    );
    expect(
      policy.longPressDelayOf(
        CatalogLeafHit(
          sectionId: 's',
          index: 0,
          leaf: CatalogLeaf.unicode('❤'),
        ),
        _recents,
        PointerDeviceKind.touch,
      ),
      isNull,
    );
  });

  testWidgets('a recent custom emoji previews instead of asking to clear the '
      'recents; its menu sends, copies and forgets it', (tester) async {
    final session = await longPress(tester, _custom('e1'));

    expect(session, isA<ContentPreviewSession>());
    expect(host.clearRecentsRequests, isEmpty);
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration);
    expect(find.text('Send Emoji'), findsOneWidget);
    expect(find.text('Copy Emoji'), findsOneWidget);
    expect(find.text('Remove from recent'), findsOneWidget);

    session!.end(const LongPressEndDetails());
    await tester.tap(find.text('Copy Emoji'));
    await tester.pump();
    expect(host.copyRequests, [
      (key: const ContentKey.document('e1'), kind: SemanticKind.customEmoji),
    ]);
  });

  testWidgets('forgetting it names the page\'s one recents list', (
    tester,
  ) async {
    final session = await longPress(tester, _custom('e2'));
    await tester.pump(ContentPreviewSession.stickerMenuDelay);
    await tester.pump(ContentPreviewSession.showDuration);
    session!.end(const LongPressEndDetails());

    await tester.tap(find.text('Remove from recent'));
    await tester.pump();
    expect(host.removeRecentRequests, [
      (key: const ContentKey.document('e2'), kind: SemanticKind.unicodeEmoji),
    ]);
    await tester.pump(ContentPreviewSession.showDuration);
    await tester.pump(const Duration(milliseconds: 16));
  });
}
