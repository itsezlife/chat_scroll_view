/// Per-message selection grants for [ChatSelectionController].
///
/// Bitfield (`extension type` over `int`). Two independent flags —
/// [selectable] and [chrome] — with [showsCheck] implied as both.
///
/// | Preset | selectable | chrome wrap | check |
/// |--------|------------|-------------|-------|
/// | [full] | yes | yes | yes |
/// | [gutterOnly] | no | yes | no |
/// | [none] | no | no | no |
///
/// **Footgun**: a raw [int] can be passed where [ChatSelectionAllowed] is
/// expected with no runtime error. Prefer the named constants below.
extension type const ChatSelectionAllowed._(int _value) {
  /// No membership, no chrome wrap.
  static const ChatSelectionAllowed none = ChatSelectionAllowed._(0);

  /// May join the selected set.
  static const ChatSelectionAllowed selectable = ChatSelectionAllowed._(1 << 0);

  /// Selection chrome wrap (mode gutter / tint host).
  static const ChatSelectionAllowed chrome = ChatSelectionAllowed._(1 << 1);

  /// Selectable + chrome + check. Default when the host predicate is null.
  ///
  /// | Bit | Name       | Value | Meaning                                      |
  /// |-----|------------|-------|----------------------------------------------|
  /// |  0  | selectable |     1 | May join [ChatSelectionController.selectedIds] |
  /// |  1  | chrome     |     2 | Mount [SelectableMessage] chrome wrap        |
  ///
  /// Bits `1 << 2` through `1 << 31` are reserved for future use.
  /// Check paint is not a bit — it is [showsCheck] (`selectable` ∩ `chrome`).
  static const ChatSelectionAllowed full = ChatSelectionAllowed._(
    (1 << 0) | (1 << 1),
  );

  /// Alias of [full].
  static const ChatSelectionAllowed all = full;

  /// Chrome wrap for mode gutter alignment without membership or check.
  static const ChatSelectionAllowed gutterOnly = chrome;

  // --- Can be expanded up to 1 << 31 --- //

  /// Defined flag constants (not composite presets).
  static const List<ChatSelectionAllowed> values = <ChatSelectionAllowed>[
    none,
    selectable,
    chrome,
  ];

  /// Whether this value contains [flag].
  bool contains(ChatSelectionAllowed flag) => (_value & flag._value) != 0;

  /// Add [flag] to this value.
  ChatSelectionAllowed add(ChatSelectionAllowed flag) =>
      ChatSelectionAllowed._(_value | flag._value);

  /// Remove [flag] from this value.
  ChatSelectionAllowed remove(ChatSelectionAllowed flag) =>
      ChatSelectionAllowed._(_value & ~flag._value);

  /// Toggle [flag] in this value.
  ChatSelectionAllowed toggle(ChatSelectionAllowed flag) =>
      ChatSelectionAllowed._(_value ^ flag._value);

  /// XOR with [other].
  ChatSelectionAllowed operator ^(ChatSelectionAllowed other) =>
      ChatSelectionAllowed._(_value ^ other._value);

  /// No flags set — excluded from selection and chrome.
  bool get isNone => _value == 0;

  /// Whether this id may join [ChatSelectionController.selectedIds].
  bool get isSelectable => contains(ChatSelectionAllowed.selectable);

  /// Whether the row should mount selection chrome ([SelectableMessage]).
  bool get showsChrome => contains(ChatSelectionAllowed.chrome);

  /// Whether bundled chrome should paint the check control.
  ///
  /// True only when both [isSelectable] and [showsChrome] — a non-selectable
  /// gutter row still shifts for mode but never shows a check.
  bool get showsCheck => isSelectable && showsChrome;
}
