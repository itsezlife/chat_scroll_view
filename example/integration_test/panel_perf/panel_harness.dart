import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real [KeyboardPanel] on a bare scaffold: no chat, no backend.
final class PanelHarness {
  PanelHarness._(this.store, this.inset, this.controller, this.data);

  final KeyboardPanelStore store;
  final ChatBottomInsetController inset;
  final KeyboardPanelController controller;
  final DefaultEmojiDataSource data;

  /// Mounts the panel. [glyphCache] and [glyphArtVersion] give the emoji atlas
  /// a persistent cache (both or neither); without them it bakes in memory.
  static Future<PanelHarness> start(
    WidgetTester tester, {
    GlyphCacheStore? glyphCache,
    GlyphArtVersionSource? glyphArtVersion,
  }) async {
    final store = KeyboardPanelStore(defaultHeight: 380);
    final data = DefaultEmojiDataSource(
      catalog: LocaleEmojiCatalogProvider(
        locale: const Locale('ru'),
        categoryTitles: EmojiCategoryTitles.russian,
        stripIconFor: EmojiTabAssets.stripIconForId,
      ),
    );
    await (store.load(), data.load()).wait;
    final inset = ChatBottomInsetController(store: store);
    final controller = KeyboardPanelController(inset: inset, store: store);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) => ChatChromeTheme(
          colors: const ChatChromeColors.dark(),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<double>(
              valueListenable: inset.heightListenable,
              builder: (context, height, child) =>
                  SizedBox(height: height, child: child),
              child: RepaintBoundary(
                child: KeyboardPanel(
                  controller: controller,
                  allow: KeyboardPanelAllow.emojiOnly,
                  labels: KeyboardPanelLabels.russian,
                  dataSource: data,
                  onEmojiSelected: (_) {},
                  onBackspace: () {},
                  glyphCache: glyphCache,
                  glyphArtVersion: glyphArtVersion,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return PanelHarness._(store, inset, controller, data);
  }

  void open() => controller.open(landscape: false);

  void dispose() {
    controller.dispose();
    inset.dispose();
    data.dispose();
  }
}
