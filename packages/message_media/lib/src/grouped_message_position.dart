/// Edge flags for one cell in a grouped-messages mosaic, stored as a bitfield
/// (`extension type` over `int`). Painters use **absent** flags for inner
/// mosaic radii ([MediaLayoutMetrics.mediaInnerRadius]) and **present** flags
/// for outer media corners ([MediaLayoutMetrics.mediaOuterRadius]).
///
/// | Bit | Name   | Value | Meaning                |
/// |-----|--------|-------|------------------------|
/// |  0  | left   |     1 | Touches mosaic left    |
/// |  1  | right  |     2 | Touches mosaic right   |
/// |  2  | top    |     4 | Touches mosaic top     |
/// |  3  | bottom |     8 | Touches mosaic bottom  |
///
/// Bits `1 << 4` through `1 << 31` are reserved.
extension type const GroupedPositionFlags._(int _value) {
  /// Bit 0 — cell abuts the mosaic’s left outer edge.
  static const GroupedPositionFlags left = GroupedPositionFlags._(1 << 0);

  /// Bit 1 — cell abuts the mosaic’s right outer edge.
  static const GroupedPositionFlags right = GroupedPositionFlags._(1 << 1);

  /// Bit 2 — cell abuts the mosaic’s top outer edge.
  static const GroupedPositionFlags top = GroupedPositionFlags._(1 << 2);

  /// Bit 3 — cell abuts the mosaic’s bottom outer edge.
  static const GroupedPositionFlags bottom = GroupedPositionFlags._(1 << 3);

  /// Zero bitfield — no outer edges (undefined for a finished calculate cell).
  static const GroupedPositionFlags none = GroupedPositionFlags._(0);

  // --- Can be expanded up to 1 << 31 --- //

  /// The four defined edge constants (excludes [none]).
  static const List<GroupedPositionFlags> values = <GroupedPositionFlags>[
    left,
    right,
    top,
    bottom,
  ];

  /// Whether every bit of [flag] is set in this bitfield.
  bool contains(GroupedPositionFlags flag) => (_value & flag._value) != 0;

  /// Bitwise OR with [flag] (set bits).
  GroupedPositionFlags add(GroupedPositionFlags flag) =>
      GroupedPositionFlags._(_value | flag._value);

  /// Clears bits present in [flag].
  GroupedPositionFlags remove(GroupedPositionFlags flag) =>
      GroupedPositionFlags._(_value & ~flag._value);

  /// XOR with [flag].
  GroupedPositionFlags toggle(GroupedPositionFlags flag) =>
      GroupedPositionFlags._(_value ^ flag._value);

  /// XOR with [other].
  GroupedPositionFlags operator ^(GroupedPositionFlags other) =>
      GroupedPositionFlags._(_value ^ other._value);

  /// Bitwise OR — combine edges (`left | right | top`).
  GroupedPositionFlags operator |(GroupedPositionFlags other) =>
      GroupedPositionFlags._(_value | other._value);

  /// Bitwise AND.
  GroupedPositionFlags operator &(GroupedPositionFlags other) =>
      GroupedPositionFlags._(_value & other._value);

  /// True when no edge bits are set.
  bool get isEmpty => _value == 0;

  /// [left] bit set.
  bool get hasLeft => contains(GroupedPositionFlags.left);

  /// [right] bit set.
  bool get hasRight => contains(GroupedPositionFlags.right);

  /// [top] bit set.
  bool get hasTop => contains(GroupedPositionFlags.top);

  /// [bottom] bit set.
  bool get hasBottom => contains(GroupedPositionFlags.bottom);
}

/// One cell’s span in a grouped-messages mosaic.
///
/// Owns: grid bounds ([minX]…[maxY]), abstract width [pw] / height fraction
/// [ph], edge [flags], optional [siblingHeights], and chat-cell span
/// bookkeeping ([spanSize], [leftSpanOffset], [edge]). Identity (Message ID)
/// lives on the host map — this type is geometry only.
///
/// Does not own: pixel rects ([MosaicLayout]), caption paint, or downloads.
///
/// ## Coordinate model
///
/// - [pw] lives in [MediaLayoutMetrics.groupedMaxSizeWidth] units (line budgets
///   typically sum to 800 before span pads).
/// - [ph] is a fraction of [MediaLayoutMetrics.groupedMaxSizeHeight].
/// - Chat list cells map `pw / 1000 * groupPhotosWidth` after [spanSize] pads;
///   [MosaicLayout] projects `pw / groupedMaxSizeWidth * mosaicWidth`.
///
/// Instances are mutable during [GroupedMessages.calculate] via [set]; treat
/// finished positions as read-only afterward.
final class GroupedMessagePosition {
  /// Creates an unset / in-progress position.
  ///
  /// Hosts normally obtain finished instances from [GroupedMessages.calculate].
  GroupedMessagePosition({
    this.minX = 0,
    this.maxX = 0,
    this.minY = 0,
    this.maxY = 0,
    this.pw = 0,
    this.ph = 0,
    this.aspectRatio = 1,
    this.flags = GroupedPositionFlags.none,
    this.spanSize = 0,
    this.leftSpanOffset = 0,
    this.edge = false,
    this.last = false,
    this.siblingHeights,
  });

  /// Inclusive left column index in the mosaic grid (`0`…`maxX` of the group).
  int minX;

  /// Inclusive right column index; equals [minX] for single-column cells.
  int maxX;

  /// Inclusive top row index.
  int minY;

  /// Inclusive bottom row index; equals [minY] unless the cell spans rows.
  int maxY;

  /// Abstract cell width in `maxSizeWidth` units (not device pixels).
  int pw;

  /// Cell height as a fraction of `maxSizeHeight` (814). When
  /// [siblingHeights] is set, painters usually sum those fractions instead.
  double ph;

  /// Input aspect (width / height) that produced this cell during calculate.
  double aspectRatio;

  /// Which mosaic outer edges this cell touches — drives corner radii.
  GroupedPositionFlags flags;

  /// Horizontal span for grid layout managers; may include
  /// [MediaLayoutMetrics.firstSpanAdditionalSize] after the edge-finish pass.
  /// Starts equal to [pw] when [set] runs.
  int spanSize;

  /// Extra left inset in abstract units for sibling layouts (incoming side).
  /// Non-zero cells are placed at `leftSpanOffset * scale` by [MosaicLayout].
  int leftSpanOffset;

  /// Avatar / bubble outer edge for this side: left for incoming, right for
  /// outgoing (set in calculate’s edge-finish pass).
  bool edge;

  /// Last member in group order (caption / time chrome hint in the Java cell).
  bool last;

  /// When non-null, fractions summed for this cell’s total height (Java
  /// sibling stack). Order is **not** top→bottom row order — e.g. narrow-first
  /// layout stores `[bottom, top]`. [MosaicLayout] derives row bands from peer
  /// cells’ `ph`, not by indexing this list.
  List<double>? siblingHeights;

  /// Writes grid + size + [flags]; resets [spanSize] to [w] (Java `set`).
  ///
  /// Does not clear [siblingHeights], [leftSpanOffset], [edge], or [last] —
  /// callers set those after [set] when needed.
  void set(
    int minX,
    int maxX,
    int minY,
    int maxY,
    int w,
    double h,
    GroupedPositionFlags flags,
  ) {
    this.minX = minX;
    this.maxX = maxX;
    this.minY = minY;
    this.maxY = maxY;
    pw = w;
    spanSize = w;
    ph = h;
    this.flags = flags;
  }

  /// Delegates to [GroupedPositionFlags.hasLeft].
  bool get hasLeft => flags.hasLeft;

  /// Delegates to [GroupedPositionFlags.hasRight].
  bool get hasRight => flags.hasRight;

  /// Delegates to [GroupedPositionFlags.hasTop].
  bool get hasTop => flags.hasTop;

  /// Delegates to [GroupedPositionFlags.hasBottom].
  bool get hasBottom => flags.hasBottom;
}
