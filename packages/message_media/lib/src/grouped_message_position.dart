import 'package:content_model/content_model.dart';

/// Edge flags for one cell of a mosaic, stored as a bitfield
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

/// One media item's cell in a mosaic, in abstract span units.
///
/// Owns: the cell's [itemId], grid bounds ([minX]…[maxY]), abstract width
/// [pw] and height fraction [ph], edge [flags], optional [siblingHeights],
/// and the span bookkeeping a grid reads ([spanSize], [leftSpanOffset],
/// [edge]). Does not own: pixel rects ([MosaicLayout]), captions or loading.
///
/// ## Coordinate model
///
/// - [pw] is in [MediaLayoutMetrics.groupedMaxSizeWidth] units (a line's
///   cells sum to 800 before the span pads).
/// - [ph] is a fraction of [MediaLayoutMetrics.groupedMaxSizeHeight].
/// - A grid maps `spanSize / 1000` of its width after the [spanSize] pads;
///   [MosaicLayout] projects `pw / groupedMaxSizeWidth * mosaicWidth`.
///
/// [GroupedMessages.calculate] fills instances through [set]; a finished
/// position is read-only by convention.
final class GroupedMessagePosition {
  /// Creates an unset position for the media item [itemId].
  ///
  /// Finished instances normally come from [GroupedMessages.calculate].
  GroupedMessagePosition({
    required this.itemId,
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

  /// The media item this cell lays out; the key a mosaic's cells, state and
  /// semantics are addressed by.
  final MediaItemId itemId;

  /// Inclusive left column index in the mosaic grid.
  int minX;

  /// Inclusive right column index; equals [minX] for a one-column cell.
  int maxX;

  /// Inclusive top row index.
  int minY;

  /// Inclusive bottom row index; equals [minY] unless the cell spans rows.
  int maxY;

  /// Abstract cell width in `groupedMaxSizeWidth` units (not pixels).
  int pw;

  /// Cell height as a fraction of `groupedMaxSizeHeight` (814). With
  /// [siblingHeights] set, the cell's height is their sum instead.
  double ph;

  /// The aspect (width / height) the cell was laid out from.
  double aspectRatio;

  /// Which outer edges of the mosaic the cell touches; drives its corner
  /// radii.
  GroupedPositionFlags flags;

  /// Horizontal span for a grid; may include
  /// [MediaLayoutMetrics.firstSpanAdditionalSize] after the edge pass.
  /// [set] resets it to the width.
  int spanSize;

  /// Extra left offset in abstract units for a cell stacked beside a tall
  /// one (incoming side). [MosaicLayout] places a non-zero offset at
  /// `leftSpanOffset * scale`.
  int leftSpanOffset;

  /// Whether this cell is on the bubble's outer edge: the left for an
  /// incoming message, the right for an outgoing one.
  bool edge;

  /// Whether this is the last item in order.
  bool last;

  /// When set, the fractions summed for this tall cell's height. Their order
  /// is not top to bottom (a narrow-first layout stores `[bottom, top]`), so
  /// [MosaicLayout] takes row bands from the peer cells' [ph], never by
  /// indexing this list.
  List<double>? siblingHeights;

  /// Writes the grid bounds, size and [flags], and resets [spanSize] to [w].
  ///
  /// Leaves [siblingHeights], [leftSpanOffset], [edge] and [last] alone;
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
