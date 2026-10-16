/// A step of roving focus across the cells of the catalog.
///
/// The four arrows are **physical** (what a key press means on screen) and
/// [next] and [previous] are **logical** (reading order), so a host binds
/// arrow keys to the first and tab-like or screen-reader steps to the second
/// without knowing the direction of any section.
enum CatalogFocusMove {
  /// One cell toward the right edge. In a right-to-left section that is the
  /// previous cell in reading order.
  right,

  /// One cell toward the left edge. In a right-to-left section that is the
  /// next cell in reading order.
  left,

  /// The cell below in the same screen column. From the last row it enters the
  /// first row of the next section that has leaves.
  down,

  /// The cell above in the same screen column. From the first row it enters
  /// the last row of the previous section that has leaves.
  up,

  /// The next cell in reading order, continuing into the next section that has
  /// leaves.
  next,

  /// The previous cell in reading order, continuing into the previous section
  /// that has leaves.
  previous,

  /// The first leaf of the catalog.
  first,

  /// The last leaf of the catalog.
  last,
}
