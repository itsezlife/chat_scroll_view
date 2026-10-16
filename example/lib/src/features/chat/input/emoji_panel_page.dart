import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';

/// The emoji page of the panel, wired to the app's [AppServices]: the one
/// place that says how this host composes `panel_pages`' [EmojiPage].
///
/// The chat's input set and the on-device acceptance harness both mount this
/// page, so what the harness measures is what the chat ships.
abstract final class EmojiPanelPage {
  /// The page's id in the shell, and the page the panel opens on first.
  static const String id = 'emoji';

  /// The emoji [PanelPage].
  ///
  /// [frames] paces the bake and [deferChrome] says, when the page mounts,
  /// whether to spread its first frame over several (the panel grows into a
  /// free slot) or mount it at once (it replaces what is on screen).
  static PanelPage of({
    required AppServices services,
    required BakeFrameSource frames,
    required bool Function() deferChrome,
  }) => PanelPage(
    id: id,
    tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'emoji'),
    capabilities: EmojiPagePolicy.pageCapabilities,
    builder: (context, host) => EmojiPage(
      host: host,
      // The catalogue, then the pack of animated emoji after its categories.
      source: services.emojiPageSource,
      searchSource: services.emojiSearch,
      preferences: services.preferences,
      entryOf: services.emojiSource.entryOf,
      assets: services.assets,
      atlasHostFactory:
          ({
            required devicePixelRatio,
            required glyphBoxExtent,
            required visible,
            required opening,
          }) => GlyphAtlasHost(
            frames: frames,
            devicePixelRatio: devicePixelRatio,
            glyphBoxExtent: glyphBoxExtent,
            visible: visible,
            opening: opening,
            memoryPressure: services.memoryPressure,
            persistence: switch (services.glyphCache) {
              final cache? => GlyphAtlasPersistence(
                cache: cache,
                artVersion: services.glyphArtVersion,
                devicePixelRatio: devicePixelRatio,
              ),
              null => null,
            },
            observer: services.glyphBakeObserver,
          ),
      // The unfiltered plan: a glyph the probe hides stays planned, so a
      // verdict never re-bakes a page (ADR 006).
      planner: services.planGlyphs,
      deferChrome: deferChrome(),
    ),
  );
}
