import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_pages/src/atlas/glyph_atlas_host.dart';
import 'package:panel_pages/src/atlas/glyph_plan.dart';
import 'package:panel_pages/src/bake/bake_activity_port.dart';
import 'package:panel_pages/src/emoji/emoji_page_policy.dart';
import 'package:panel_pages/src/page/catalog_page.dart';
import 'package:panel_pages/src/page/catalog_page_controller.dart';
import 'package:panel_shell/panel_shell.dart';

/// Builds the glyph plan of the page's collections, or null while they are not
/// ready to be planned. [GlyphPlan.of] is the default.
typedef GlyphPlanner = GlyphPlan? Function(List<Collection> collections);

/// Builds the atlas host of an emoji page, once the density of its view is
/// known.
///
/// The composition root owns everything about *how* glyphs are baked (the
/// frame source, the disk cache, the glyph-support probe's observer, memory
/// pressure); the page owns *what* and *when*. [glyphBoxExtent] and
/// [devicePixelRatio] are the page's to say, and [visible] and [opening] are
/// the panel's presence, which the host follows.
typedef GlyphAtlasHostFactory =
    GlyphAtlasHost Function({
      required double devicePixelRatio,
      required double glyphBoxExtent,
      required listen.ValueListenable<bool> visible,
      required listen.ValueListenable<bool> opening,
    });

/// What the emoji page keeps across being unmounted: the catalogue's controller
/// and the glyph atlas host.
///
/// The page widget is torn down every time the panel closes; the baked pages
/// must not be, and neither must their being the scope's glyph source: the
/// scope is the host's, and surfaces outside the panel (the composer's inline
/// emoji) draw through it. The shell's controller owns this through the page's
/// registry; disposing it takes the atlas back out of the scope, then disposes
/// the host.
final class EmojiPageController extends CatalogPageController {
  /// The atlas host, or null until the page knows its density, and for a page
  /// that bakes nothing.
  GlyphAtlasHost? atlasHost;

  /// The scope the page registered its atlas with, so disposing the
  /// controller can take it out again. Null before the page mounts.
  AssetCacheScope? assets;

  @override
  void dispose() {
    _releaseGlyphSource();
    atlasHost?.dispose();
    atlasHost = null;
    super.dispose();
  }

  // Leaves the scope without a source of ours: what is registered is either
  // the atlas about to be disposed or the stand-in that waited for it.
  void _releaseGlyphSource() {
    final scope = assets;
    assets = null;
    if (scope == null) return;
    final bound = scope.glyphSource;
    if (bound == null) return;
    if (identical(bound, _PendingGlyphSource.instance) ||
        identical(bound, atlasHost?.source.value)) {
      scope.glyphSource = null;
    }
  }
}

/// The glyph source of a scope whose atlas is on its way: it knows no glyph, so
/// every glyph attached is a circle until the real atlas replaces it, instead
/// of a paragraph drawn in the meantime and kept for good.
final class _PendingGlyphSource implements GlyphSpriteSource {
  const _PendingGlyphSource._();

  static const _PendingGlyphSource instance = _PendingGlyphSource._();

  @override
  AtlasSprite? spriteOf(String glyph) => null;

  @override
  SpritePageHold? holdPageOf(String glyph) => null;

  // Every glyph waits: the atlas that will draw it is on its way, and a
  // paragraph drawn meanwhile is the cost the atlas exists to avoid.
  @override
  bool waitsForSprite(String glyph) => true;

  @override
  void addPageListener(void Function(int pageIndex) listener) {}

  @override
  void removePageListener(void Function(int pageIndex) listener) {}
}

/// The emoji page: the emoji catalogue, its category strip, search results and
/// variant picker, over the shared [CatalogPage] scaffold.
///
/// A thin composition: the sections, titles, geometry, recents action, picker
/// and strip are [EmojiPagePolicy]'s, the viewport, loading, search and
/// reporting are the scaffold's, and this widget adds what only a page that
/// shows baked glyphs knows.
///
/// ## Loading
///
/// Emoji are in memory, and the atlas has to be planned for all of them before
/// the first glyph is drawn: a glyph that attaches while no atlas exists is
/// drawn as text, and text on a baking platform is the paragraph rasterisation
/// the atlas exists to avoid. So the page asks every collection to load as soon
/// as it is listed (and the rest of every page), rather than as sections come
/// near. A source that publishes `loaded` in the same turn it is asked (the
/// emoji source does, within one microtask) has every collection loaded before
/// the first frame that could draw a glyph.
///
/// ## The atlas
///
/// With an [atlasHostFactory], the page plans a glyph atlas from [planner]'s
/// plan of the source's collections (by default exactly what the page shows:
/// the chosen variant of each emoji, then recents the catalogue lacks), keeps
/// it in its [EmojiPageController], and wires it: the host's layered source
/// is the `assets` scope's glyph source, and the scaffold forwards the
/// catalogue's motion and visible band to the host. When the plan grows (a
/// variant chosen for the first time) the host bakes the new glyphs in a layer
/// of their own, and keeps every glyph it ever drew, for the composer; when
/// the density changes it plans again behind the old art. With
/// none the page draws text, which is right on the web and for a page
/// embedded on its own.
///
/// Until the plan exists (a source that pages its collections is not ready to
/// be planned) the scope's glyph source is a stand-in that knows nothing, so
/// the glyphs attached meanwhile are circles that move onto the atlas when it
/// arrives, never paragraphs; a platform that bakes nothing takes the stand-in
/// out and they are drawn as text. The atlas stays the scope's glyph source
/// after the page is unmounted, for the surfaces outside the panel that draw
/// through the same scope, until the controller is disposed.
///
/// ## Paced mount
///
/// With [deferChrome] the page mounts in steps, one frame each: the grid
/// first, then the search field, then the strip. A first frame that carried
/// the catalogue, a text field and the strip together costs more than a 120 Hz
/// frame. A panel that opens with an animation mounts its page while nothing
/// moves, so spreading the cost is free; a panel already on screen when the
/// page mounts (it replaces the keyboard) must not, or the chrome would pop
/// in. Read once, when the page mounts.
///
/// Requires the chrome theme and strings scopes.
class EmojiPage extends StatefulWidget {
  /// The emoji page of [host], showing [source] and searching [searchSource].
  const EmojiPage({
    required this.host,
    required this.source,
    required this.searchSource,
    required this.preferences,
    required this.entryOf,
    required this.assets,
    this.atlasHostFactory,
    this.planner = GlyphPlan.of,
    this.deferChrome = false,
    this.searchDebounce = DebouncedSearch.defaultDebounce,
    super.key,
  });

  /// The page's connection to the shell; fixed for the life of the widget.
  final PanelPageHost host;

  /// The emoji collections: the recents, then one per category.
  final CollectionSource source;

  /// Where search results come from.
  final SearchSource searchSource;

  /// Where the variant a user chose per emoji is kept.
  final PreferenceStore preferences;

  /// The catalogue's answer for a key; see [EmojiEntryOf].
  final EmojiEntryOf entryOf;

  /// The asset cache the grid draws through. The page sets its glyph source
  /// when it has an atlas; the host owns and disposes it.
  final AssetCacheScope assets;

  /// Creates the atlas host, or null where nothing is baked.
  final GlyphAtlasHostFactory? atlasHostFactory;

  /// What the atlas is planned for, from the source's collections.
  final GlyphPlanner planner;

  /// Whether the strip mounts in the frames after the grid.
  final bool deferChrome;

  /// How long typing pauses before a search runs.
  final Duration searchDebounce;

  /// Horizontal inset of the grid.
  static const double gridPadH = 5;

  /// Left padding of the grid under the pointer arrangement.
  static const double pointerGridPadStart = 8;

  /// Right padding of the grid under the pointer arrangement.
  static const double pointerGridPadEnd = 4;

  /// What the bottom bar and the safe area do not cover, kept clear below the
  /// last row.
  ///
  /// The bottom padding the shell passes down is the room of the floating bar
  /// (and, under touch, the safe inset). Under the pointer arrangement the
  /// catalogue ends above the strip, so the padding is still right: the bar
  /// floats over the end of the catalogue's last rows, the strip is not under
  /// it, and the safe inset belongs to the shell there.
  static const double gridPadBottom = 4;

  @override
  State<EmojiPage> createState() => _EmojiPageState();
}

class _EmojiPageState extends State<EmojiPage> {
  late final EmojiPageController _controller;
  late EmojiPagePolicy _policy;
  final _stripReady = listen.ValueNotifier<bool>(true);
  final _fieldReady = listen.ValueNotifier<bool>(true);
  GlyphSpriteSource? _boundSource;
  BakeActivityPort? _bake;
  var _density = 0.0;
  var _dependenciesReady = false;

  PanelPageHost get _host => widget.host;

  @override
  void initState() {
    super.initState();
    _controller = _host.controllers.obtain(
      _host.pageId,
      EmojiPageController.new,
    );
    _policy = _newPolicy();
    widget.source.collections.addListener(_onCollections);
    if (widget.deferChrome) {
      _fieldReady.value = false;
      _stripReady.value = false;
      // The grid is frame one, the search field frame two and the strip frame
      // three: a first frame that carried all three costs more than a 120 Hz
      // frame. The bands of both are reserved from the first, so nothing moves
      // when they arrive.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fieldReady.value = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _stripReady.value = true;
        });
      });
    }
    _onCollections();
  }

  EmojiPagePolicy _newPolicy() => EmojiPagePolicy(
    host: _host,
    entryOf: widget.entryOf,
    preferences: widget.preferences,
    stripReady: _stripReady,
    assets: widget.assets,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final density = MediaQuery.devicePixelRatioOf(context);
    final first = !_dependenciesReady;
    _dependenciesReady = true;
    if (!first && density == _density) return;
    _density = density;
    _ensureAtlasHost();
    _controller.atlasHost?.devicePixelRatio = density;
    _bindAtlas(notify: !first);
    _planAtlas();
  }

  @override
  void didUpdateWidget(EmojiPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      oldWidget.source.collections.removeListener(_onCollections);
      widget.source.collections.addListener(_onCollections);
      _onCollections();
    }
    if (!identical(oldWidget.entryOf, widget.entryOf) ||
        !identical(oldWidget.preferences, widget.preferences) ||
        !identical(oldWidget.assets, widget.assets)) {
      _policy = _newPolicy();
    }
    if (!identical(oldWidget.assets, widget.assets)) {
      _controller._releaseGlyphSource();
      _boundSource = null;
      _bindAtlas(notify: false);
    }
  }

  @override
  void dispose() {
    widget.source.collections.removeListener(_onCollections);
    _controller.atlasHost?.source.removeListener(_onAtlas);
    // The atlas stays the scope's glyph source: the host outlives this widget,
    // and so do the composer's inline emoji drawn through the same scope. The
    // controller takes it out when the shell disposes it.
    _fieldReady.dispose();
    _stripReady.dispose();
    super.dispose();
  }

  // --- Loading and planning -------------------------------------------------

  void _onCollections() {
    final collections = widget.source.collections.value;
    for (final collection in collections) {
      switch (collection.contents) {
        case CollectionContents$Idle():
          unawaited(widget.source.load(collection.id));
        case CollectionContents$Loaded(:final nextPageToken)
            when nextPageToken != null:
          unawaited(widget.source.loadMore(collection.id));
        case CollectionContents$Loaded() ||
            CollectionContents$Loading() ||
            CollectionContents$Failed():
          break;
      }
    }
    _planAtlas();
  }

  void _planAtlas() {
    final atlasHost = _controller.atlasHost;
    if (atlasHost == null) return;
    final plan = widget.planner(widget.source.collections.value);
    if (plan == null) return;
    atlasHost.sync(plan);
    // A platform that bakes nothing says so now, with no atlas to signal it:
    // the glyphs that waited for one are drawn as text from here on.
    _applyAtlas(atlasHost.source.value, notify: false);
  }

  // --- The atlas ------------------------------------------------------------

  void _ensureAtlasHost() {
    final factory = widget.atlasHostFactory;
    if (factory == null || _controller.atlasHost != null) return;
    final created = factory(
      devicePixelRatio: _density,
      glyphBoxExtent: EmojiPagePolicy.glyphBoxExtent,
      visible: _host.panelVisible,
      opening: _host.panelOpening,
    );
    _controller.atlasHost = created;
  }

  // Makes the scope draw from the host's current atlas and follows its
  // replacements. Called with notify false from a lifecycle method, where the
  // build that follows reads the result anyway.
  void _bindAtlas({required bool notify}) {
    final atlasHost = _controller.atlasHost;
    if (atlasHost == null) return;
    _controller.assets = widget.assets;
    atlasHost.source
      ..removeListener(_onAtlas)
      ..addListener(_onAtlas);
    _applyAtlas(atlasHost.source.value, notify: notify);
  }

  void _onAtlas() =>
      _applyAtlas(_controller.atlasHost!.source.value, notify: true);

  void _applyAtlas(GlyphSpriteSource? atlas, {required bool notify}) {
    final atlasHost = _controller.atlasHost;
    // No atlas yet: wait for it unless the platform has none to wait for.
    // The scope rebinds the glyphs on screen to the new source in place, so a
    // replan swaps art without re-attaching a leaf.
    widget.assets.glyphSource = switch (atlas) {
      final baked? => baked,
      null when atlasHost?.bakesNothing ?? true => null,
      null => _PendingGlyphSource.instance,
    };
    if (identical(atlas, _boundSource)) return;
    _boundSource = atlas;
    // The host reaches every atlas it keeps, including the ones it adds.
    final port = switch (atlas) {
      _? => atlasHost,
      null => null,
    };
    if (notify && mounted) {
      setState(() => _bake = port);
    } else {
      _bake = port;
    }
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) => CatalogPage(
    host: _host,
    source: widget.source,
    searchSource: widget.searchSource,
    policy: _policy,
    assets: widget.assets,
    bake: _bake,
    searchFieldReady: _fieldReady,
    searchDebounce: widget.searchDebounce,
    padding: switch (PanelArrangementScope.of(context)) {
      PanelArrangement.touch => EdgeInsets.fromLTRB(
        EmojiPage.gridPadH,
        0,
        EmojiPage.gridPadH,
        MediaQuery.paddingOf(context).bottom + EmojiPage.gridPadBottom,
      ),
      // The reference desktop client's list: 8 in from the left (its
      // corner), 4 short of the right (its scrollbar's room less the margin
      // the columns may take).
      PanelArrangement.pointer => EdgeInsets.fromLTRB(
        EmojiPage.pointerGridPadStart,
        0,
        EmojiPage.pointerGridPadEnd,
        MediaQuery.paddingOf(context).bottom + EmojiPage.gridPadBottom,
      ),
    },
  );
}
