import 'dart:async';

import 'package:emoji_data/src/catalog/emoji_catalog_search.dart';
import 'package:emoji_data/src/emoji_catalog_provider.dart';
import 'package:emoji_data/src/emoji_category_spec.dart';
import 'package:emoji_data/src/emoji_data_listener.dart';
import 'package:emoji_data/src/emoji_data_source.dart';
import 'package:emoji_data/src/emoji_item.dart';
import 'package:emoji_data/src/emoji_pick_source.dart';
import 'package:emoji_data/src/emoji_recents_store.dart';
import 'package:emoji_data/src/locale_emoji_catalog_provider.dart';
import 'package:emoji_data/src/skin_tone_prefs.dart';

/// Default [EmojiDataSource]: locale catalog + frequency recents + skin tones.
final class DefaultEmojiDataSource extends EmojiDataSource
    with EmojiDataListenerMixin {
  DefaultEmojiDataSource({
    EmojiCatalogProvider? catalog,
    EmojiRecentsStore? recentsStore,
    SkinTonePrefs? skinTonePrefs,
  })  : catalog = catalog ?? LocaleEmojiCatalogProvider(),
        recentsStore = recentsStore ?? SharedPrefsEmojiRecentsStore(),
        skinTonePrefs = skinTonePrefs ?? SharedPrefsSkinTonePrefs();

  final EmojiCatalogProvider catalog;
  final EmojiRecentsStore recentsStore;
  final SkinTonePrefs skinTonePrefs;

  var _ready = false;
  List<EmojiCategorySpec> _categories = <EmojiCategorySpec>[];
  List<UnicodeEmojiItem> _searchIndex = <UnicodeEmojiItem>[];

  @override
  bool get isReady => _ready;

  @override
  List<EmojiCategorySpec> get categories =>
      List<EmojiCategorySpec>.unmodifiable(_categories);

  @override
  List<String> get recentGlyphs => recentsStore.recents;

  @override
  Future<void> load() async {
    await Future.wait<void>([recentsStore.load(), skinTonePrefs.load()]);
    await _reloadCatalog();
    _ready = true;
    notifyDataChanged();
  }

  /// Reloads categories from [catalog] (e.g. after host locale / title change).
  ///
  /// Does not re-read recents or skin prefs. Emits [notifyDataChanged].
  Future<void> reloadCatalog() async {
    await _reloadCatalog();
    notifyDataChanged();
  }

  Future<void> _reloadCatalog() async {
    _categories = await catalog.loadCategories();
    _searchIndex = _categories
        .expand((c) => c.items.whereType<UnicodeEmojiItem>())
        .toList(growable: false);
  }

  @override
  FutureOr<List<EmojiItem>> search(String query) async {
    if (!_ready) return const <EmojiItem>[];
    return EmojiCatalogSearch.search(query, _searchIndex);
  }

  @override
  Future<void> recordPick(
    EmojiItem item, {
    required EmojiPickSource source,
  }) async {
    if (item is! UnicodeEmojiItem) return;
    final changed = await recentsStore.recordPick(item.glyph, source: source);
    if (changed != null) notifyDataChanged();
  }

  @override
  Future<void> clearRecents() async {
    await recentsStore.clear();
    notifyDataChanged();
  }

  @override
  int skinToneFor(String base) => skinTonePrefs.toneFor(base);

  @override
  Future<void> setSkinTone(String base, int toneIndex) async {
    await skinTonePrefs.setTone(base, toneIndex);
    notifyDataChanged();
  }

  @override
  void dispose() {
    disposeDataListeners();
  }
}
