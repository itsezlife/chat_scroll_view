/// The draft options' live preview: the draft drawn as the chat's own
/// outgoing bubble, the card from the page under the draft's options, the
/// text not selectable, and a tap on a link handed to the overlay with its
/// outline in the bubble's coordinates.
///
/// **Seam:** `ChatDraftPreviewBubble` under the app's chrome and media
/// scopes, over a `ChatBodyHost` whose media host lays the card out with the
/// Android media policy.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart' show ChatMarkdownBody;
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_draft_options.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_media_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_draft_preview_bubble.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/testing.dart' show FakeAssetProducer;

final _url = Uri.parse('https://site.example/a');

final _page = LinkPreview(
  url: _url,
  siteName: 'Site',
  title: 'A page',
  description: const RichText.plain('About the page.'),
);

void main() {
  late ContentAssetScope scope;
  late ValueNotifier<LargeEmojiPolicy> emoji;
  late MessageMediaState state;
  late ChatBodyHost bodies;
  late List<(String, Path)> taps;

  setUp(() {
    scope = ContentAssetScope.withMedia(producer: FakeAssetProducer());
    emoji = ValueNotifier(const LargeEmojiPolicy(enabled: true));
    state = MessageMediaState();
    final media = ChatMediaHost(
      chatId: 'chat-1',
      resolver: FakeLinkPreviewResolver(),
      policy: const MessageMediaPolicy.android(),
    );
    bodies = ChatBodyHost(assets: scope, policy: emoji, media: media);
    taps = [];
    addTearDown(scope.dispose);
    addTearDown(emoji.dispose);
    addTearDown(state.dispose);
    addTearDown(media.dispose);
  });

  DraftOptionsPreview previewOf(
    String text, {
    required LinkPreviewState page,
    bool invertMedia = false,
  }) => DraftOptionsPreview(
    text: RichText.plain(text),
    part: DraftLinkPart(
      options: LinkPreviewOptions(url: _url),
      invertMedia: invertMedia,
    ),
    page: page,
    onLinkTap: (url, contour) => taps.add((url, contour)),
    linkCursor: SystemMouseCursors.click,
  );

  Future<void> pump(WidgetTester tester, DraftOptionsPreview preview) async {
    tester.view
      ..physicalSize = const Size(420, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: ChromeStringsScope(
            strings: demoChromeStrings,
            child: ChromeTextRoot(child: child!),
          ),
        ),
        home: ContentAssetProvider(
          scope: scope,
          child: MessageMediaStateScope(
            state: state,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: ChatDraftPreviewBubble(
                  preview: preview,
                  bodies: bodies,
                  chatId: 'chat-1',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a loaded page draws the card in the chat bubble', (
    tester,
  ) async {
    await pump(
      tester,
      previewOf('see $_url', page: LinkPreviewState.loaded(_page)),
    );

    expect(find.text('A page'), findsOneWidget);
    expect(find.byType(ChatMarkdownBody), findsOneWidget);
    expectChromeText(tester, within: find.byType(ChatDraftPreviewBubble));
  });

  testWidgets('a pending page draws no card', (tester) async {
    await pump(tester, previewOf('see $_url', page: LinkPreviewState.pending));

    expect(find.text('A page'), findsNothing);
    expect(find.byType(ChatMarkdownBody), findsOneWidget);
  });

  testWidgets('a tap on a link reports it with its outline in the bubble', (
    tester,
  ) async {
    await pump(
      tester,
      previewOf('$_url', page: LinkPreviewState.loaded(_page)),
    );
    final body = tester.getRect(find.byType(ChatMarkdownBody));
    final bubble = tester.getRect(find.byType(ChatDraftPreviewBubble));

    await tester.tapAt(body.topLeft + const Offset(12, 8));
    await tester.pump();

    final [(url, contour)] = taps;
    expect(url, '$_url');
    final outline = contour.getBounds().shift(bubble.topLeft);
    expect(outline.overlaps(body), isTrue);
    expect(outline.contains(body.topLeft + const Offset(12, 8)), isTrue);
  });

  testWidgets('a tap off the links reports nothing and selects nothing', (
    tester,
  ) async {
    await pump(
      tester,
      previewOf('hello $_url', page: LinkPreviewState.loaded(_page)),
    );
    final body = tester.getRect(find.byType(ChatMarkdownBody));

    await tester.tapAt(body.topLeft + const Offset(6, 8));
    await tester.longPressAt(body.topLeft + const Offset(6, 8));
    await tester.pump();

    expect(taps, isEmpty);
  });

  testWidgets("a mouse over a link takes the preview's link cursor", (
    tester,
  ) async {
    await pump(
      tester,
      previewOf('$_url', page: LinkPreviewState.loaded(_page)),
    );
    final body = tester.getRect(find.byType(ChatMarkdownBody));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    await mouse.moveTo(body.topLeft + const Offset(12, 8));
    await tester.pump();

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });

  testWidgets('a link tap without an outline reports the missing hook', (
    tester,
  ) async {
    final diagnostics = RecordingDiagnostics.install();

    ChatDraftPreviewBubble.deliverLinkTap(
      previewOf('$_url', page: LinkPreviewState.loaded(_page)),
      url: '$_url',
      contour: null,
      shift: Offset.zero,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
    );

    expect(diagnostics.whereOp(ChatDraftOptionsOp.wiringMissing), [
      isChatEvent(
        fields: {'hook': 'onLinkTap'},
        correlation: const ChatCorrelation(chatId: 'chat-1'),
      ),
    ]);
    expect(taps.single.$1, '$_url');
  });
}
