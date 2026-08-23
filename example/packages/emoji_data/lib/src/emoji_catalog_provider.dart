import 'package:emoji_data/src/emoji_category_spec.dart';

/// Loads the emoji category catalog (host or bundled default).
abstract class EmojiCatalogProvider {
  Future<List<EmojiCategorySpec>> loadCategories();
}
