import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// One tab of the emoji category strip: a semantic icon, and the catalogue
/// groups the tab leads to.
///
/// A tab can cover several groups (smileys and people are one tab, as in
/// the reference client): tapping it lands on the first of its sections that
/// the page shows, and the tab is active while the user is in any of them.
@immutable
final class EmojiCategoryTab {
  /// A tab named [id], painted as [icon], covering the catalogue groups
  /// [groupIds] (or the recents when [recents]).
  const EmojiCategoryTab({
    required this.id,
    required this.icon,
    this.groupIds = const [],
    this.recents = false,
  });

  /// Stable name of the tab.
  final String id;

  /// The chrome icon of the tab.
  final ChromeIconId icon;

  /// The category ids (`CollectionId.category`) the tab leads to, in order.
  final List<String> groupIds;

  /// Whether the tab leads to the recents instead.
  final bool recents;

  /// Whether the section of [collection] belongs to this tab.
  bool covers(CollectionId collection) => switch (collection) {
    CollectionId$Category(:final id) => groupIds.contains(id),
    _ => recents && collection == CollectionId.recent,
  };

  /// The category id whose title names the tab: the first group's. Recents
  /// have none (the tab is named by the recents title).
  String? get titleGroup => groupIds.isEmpty ? null : groupIds.first;

  @override
  String toString() => 'EmojiCategoryTab($id)';
}

/// The tabs of the emoji strip and their icons.
///
/// The ids of the groups are the Unicode group slugs the emoji catalogue uses;
/// a group no tab names has a section but no tab. Presentation owns the
/// pictures: [icons] are painters a host registers (or [EmojiTabIconScope]
/// does) under these ids, so a host can restyle a tab by registering its own.
abstract final class EmojiCategories {
  /// Recently used emoji.
  static const EmojiCategoryTab recents = EmojiCategoryTab(
    id: 'recents',
    icon: ChromeIconId('emoji.recents'),
    recents: true,
  );

  /// Smileys and people.
  static const EmojiCategoryTab smileys = EmojiCategoryTab(
    id: 'smileys',
    icon: ChromeIconId('emoji.smileys'),
    groupIds: ['smileys-emotion', 'people-body'],
  );

  /// Animals and nature.
  static const EmojiCategoryTab animals = EmojiCategoryTab(
    id: 'animals',
    icon: ChromeIconId('emoji.animals'),
    groupIds: ['animals-nature'],
  );

  /// Food and drink.
  static const EmojiCategoryTab food = EmojiCategoryTab(
    id: 'food',
    icon: ChromeIconId('emoji.food'),
    groupIds: ['food-drink'],
  );

  /// Travel and places.
  static const EmojiCategoryTab travel = EmojiCategoryTab(
    id: 'travel',
    icon: ChromeIconId('emoji.travel'),
    groupIds: ['travel-places'],
  );

  /// Activities.
  static const EmojiCategoryTab activities = EmojiCategoryTab(
    id: 'activities',
    icon: ChromeIconId('emoji.activities'),
    groupIds: ['activities'],
  );

  /// Objects.
  static const EmojiCategoryTab objects = EmojiCategoryTab(
    id: 'objects',
    icon: ChromeIconId('emoji.objects'),
    groupIds: ['objects'],
  );

  /// Symbols.
  static const EmojiCategoryTab symbols = EmojiCategoryTab(
    id: 'symbols',
    icon: ChromeIconId('emoji.symbols'),
    groupIds: ['symbols'],
  );

  /// Flags.
  static const EmojiCategoryTab flags = EmojiCategoryTab(
    id: 'flags',
    icon: ChromeIconId('emoji.flags'),
    groupIds: ['flags'],
  );

  /// Every tab, in strip order.
  static const List<EmojiCategoryTab> tabs = [
    recents,
    smileys,
    animals,
    food,
    travel,
    activities,
    objects,
    symbols,
    flags,
  ];

  /// The tab that covers the section of [collection], or null for none.
  static EmojiCategoryTab? tabOf(CollectionId collection) {
    for (final tab in tabs) {
      if (tab.covers(collection)) return tab;
    }
    return null;
  }
}
