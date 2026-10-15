import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_chrome/src/panel/emoji_glyph_atlas_host.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter_test/flutter_test.dart';

/// An emoji source that is ready at once and whose tones the test sets.
class _Data extends EmojiDataSource with EmojiDataListenerMixin {
  _Data(this.categories);

  @override
  final List<EmojiCategorySpec> categories;

  bool ready = true;
  final Map<String, int> tones = {};

  @override
  bool get isReady => ready;

  void changed() => notifyDataChanged();

  @override
  int skinToneFor(String base) => tones[base] ?? 0;

  @override
  List<String> get recentGlyphs => const [];
  @override
  Future<void> load() async {}
  @override
  FutureOr<List<EmojiItem>> search(String query) => const [];
  @override
  Future<void> recordPick(EmojiItem item, {required EmojiPickSource source}) =>
      Future.value();
  @override
  Future<void> clearRecents() => Future.value();
  @override
  Future<void> setSkinTone(String base, int toneIndex) => Future.value();
  @override
  void dispose() => disposeDataListeners();
}

EmojiCategorySpec _category(String id, List<EmojiItem> items) =>
    EmojiCategorySpec(id: id, title: id, items: items);

void main() {
  late FakeBakeFrameSource frames;
  late _Data data;
  late List<GlyphAtlas> created;

  setUp(() {
    frames = FakeBakeFrameSource();
    created = [];
    data = _Data([
      _category('faces', const [
        EmojiItem.unicode(glyph: '😀'),
        EmojiItem.unicode(glyph: '😁'),
      ]),
      _category('hands', const [
        EmojiItem.unicode(glyph: '👍', supportsSkinTone: true),
      ]),
    ]);
  });
  tearDown(() => data.dispose());

  EmojiGlyphAtlasHost host({bool bakes = true}) {
    final host = EmojiGlyphAtlasHost(
      dataSource: data,
      frames: frames,
      devicePixelRatio: 2,
      rasteriser: FakeGlyphRasteriser(),
      store: FakeGlyphPageStore(),
      atlasFactory:
          ({
            required index,
            required rasteriser,
            required store,
            required frames,
            required clock,
            required panelVisible,
            required panelOpening,
          }) {
            if (!bakes) return null;
            final atlas = GlyphAtlas(
              index: index,
              rasteriser: rasteriser,
              store: store,
              frames: frames,
              clock: clock,
              panelVisible: panelVisible,
              panelOpening: panelOpening,
            );
            created.add(atlas);
            return atlas;
          },
    );
    addTearDown(host.dispose);
    return host;
  }

  test('has no atlas until the data is ready', () {
    data.ready = false;
    final h = host()..sync(recents: const []);

    expect(h.atlas, isNull);
    expect(created, isEmpty);

    data.ready = true;
    h.sync(recents: const []);
    expect(h.atlas, isNotNull);
  });

  test('plans the glyphs the grid will show, recents first', () {
    final h = host()..sync(recents: const ['🔥']);

    final index = h.atlas!.index;
    expect(index.glyphCount, 4);
    expect(index.placementOf('🔥')!.source, index.layout.glyphRect(0));
    for (final glyph in ['😀', '😁', '👍']) {
      expect(index.placementOf(glyph), isNotNull, reason: glyph);
    }
  });

  test('plans the tone the user chose, not the base glyph', () {
    data.tones['👍'] = 2;
    final h = host()..sync(recents: const []);

    final tone = EmojiSkinTone.apply('👍', 2);
    expect(h.atlas!.index.placementOf(tone), isNotNull);
    expect(h.atlas!.index.placementOf('👍'), isNull);
  });

  test('keeps its atlas while every glyph is still planned', () {
    final h = host()..sync(recents: const ['😀']);
    final first = h.atlas;
    var notified = 0;
    h.addListener(() => notified++);

    h.sync(recents: const ['😁']);
    h.sync(recents: const []);

    expect(h.atlas, same(first));
    expect(notified, 0);
  });

  test(
    'plans again, and says so, when a glyph appears that is not planned',
    () {
      final h = host()..sync(recents: const []);
      final first = h.atlas!;
      var notified = 0;
      h.addListener(() => notified++);

      data.tones['👍'] = 3;
      h.sync(recents: const []);

      expect(h.atlas, isNot(same(first)));
      expect(
        h.atlas!.index.placementOf(EmojiSkinTone.apply('👍', 3)),
        isNotNull,
      );
      expect(notified, 1);
      // The replaced atlas is released, not left baking.
      expect(first.spriteOf('😀'), isNull);
      expect(frames.hasPendingRequest, isFalse);
    },
  );

  test('a platform that does not bake gets no atlas and starts no bake', () {
    final h = host(bakes: false)..sync(recents: const []);

    expect(h.atlas, isNull);
    expect(frames.requested, 0);
  });

  test('bakes only while the panel is visible and not opening', () {
    final h = host()..sync(recents: const []);

    expect(frames.hasPendingRequest, isFalse, reason: 'hidden');

    h.panelVisible.value = true;
    expect(frames.hasPendingRequest, isTrue);

    h.panelOpening.value = true;
    expect(frames.hasPendingRequest, isFalse);

    h.panelOpening.value = false;
    expect(frames.hasPendingRequest, isTrue);
  });

  test('dispose releases the atlas and the pause notifiers', () {
    final h = host()..sync(recents: const []);
    final atlas = h.atlas!;

    h
      ..dispose()
      ..dispose();

    expect(atlas.spriteOf('😀'), isNull);
    expect(h.atlas, isNull);
    expect(() => h.panelVisible.value = true, throwsFlutterError);
  });
}
