import 'package:chat_chrome/src/legacy_emoji/emoji_category_spec.dart';

/// Loads the emoji category catalog (host or bundled default).
abstract class EmojiCatalogProvider {
  Future<List<EmojiCategorySpec>> loadCategories();
}
