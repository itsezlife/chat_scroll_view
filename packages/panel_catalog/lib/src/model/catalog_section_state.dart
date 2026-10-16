/// Where the collection behind a [CatalogSection] stands, as far as painting
/// is concerned.
///
/// Mirrors the states of a collection's contents without importing them: a
/// page maps `idle` and `loading` to [loading], `failed` to [failed] and
/// `loaded` to [loaded]. A loaded collection with no items is not a state of
/// its own: it is [loaded] with no leaves, and the section's empty message
/// ([CatalogSection.emptyMessage]) says what to show.
///
/// The viewport paints a state, it never changes one: loading, retrying and
/// pagination belong to whoever publishes the snapshot, which learns that a
/// section needs them from the controller's near-viewport events.
enum CatalogSectionState {
  /// The contents are on their way (or not requested yet): the section paints
  /// skeleton leaves after the leaves it already has.
  loading,

  /// The last load failed: the section paints the same skeleton leaves as
  /// [loading], never an error. Whether and when to retry is the owner's.
  failed,

  /// The contents are all there is: the section paints its leaves, or its
  /// empty message row when it has none and a message.
  loaded,
}
