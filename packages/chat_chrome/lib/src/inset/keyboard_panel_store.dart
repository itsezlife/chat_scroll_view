import 'package:shared_preferences/shared_preferences.dart';

/// Persists keyboard-panel chrome prefs: IME/panel height and selected type tab.
///
/// **Owns:** portrait/landscape panel target height and the selected type-tab
/// index. All keys use the `keyboard_panel_*` prefix with **no** legacy
/// dual-read of older names.
///
/// **Does not own:** live IME animation frames, inset occupancy math
/// ([ChatBottomInsetController]), or chrome open/search SoT
/// ([KeyboardPanelController]).
///
/// Call [load] once before [heightFor] / [selectedPage] reads. Concurrent or
/// repeat [load] callers share one in-flight future and no-op after the first
/// successful load. [record] never shrinks a sane stored height from a single
/// sample (hide-animation frames must not poison the panel target).
final class KeyboardPanelStore {
  /// Creates a store. Call [load] once before first [heightFor].
  KeyboardPanelStore({
    this.minRecordableHeight = 50,
    this.defaultHeight = 200,
  });

  /// Minimum height to persist from a settled IME sample.
  final double minRecordableHeight;

  /// Prefs fallback when no sane height is stored.
  final double defaultHeight;

  /// Reject poisoned mid-animation samples below this.
  static const double minSaneKeyboardHeight = 180;

  /// Prefs key for portrait panel / IME height.
  static const String portraitHeightKey = 'keyboard_panel_height';

  /// Prefs key for landscape panel / IME height.
  static const String landscapeHeightKey = 'keyboard_panel_height_land';

  /// Prefs key for the selected type tab (`0` emoji / `1` stickers / `2` GIFs).
  static const String selectedPageKey = 'keyboard_panel_selected_page';

  SharedPreferences? _prefs;
  Future<void>? _loadFuture;
  double _portrait = 200;
  double _landscape = 200;
  int _selectedPage = 0;

  /// Whether [load] completed.
  bool get isReady => _prefs != null;

  /// Selected type tab index (0 emoji / 1 stickers / 2 GIFs).
  int get selectedPage => _selectedPage;

  /// Loads prefs into memory. Scrubs poisoned mid-animation heights.
  ///
  /// Safe to call more than once — concurrent / repeat callers share one
  /// in-flight future and no-op after the first successful load.
  Future<void> load() {
    final existing = _loadFuture;
    if (existing != null) return existing;
    return _loadFuture = _loadOnce();
  }

  Future<void> _loadOnce() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _portrait = _sanitize(prefs.getDouble(portraitHeightKey) ?? defaultHeight);
    _landscape = _sanitize(
      prefs.getDouble(landscapeHeightKey) ?? defaultHeight,
    );
    _selectedPage = prefs.getInt(selectedPageKey) ?? 0;
    if (_portrait != (prefs.getDouble(portraitHeightKey) ?? defaultHeight)) {
      await prefs.setDouble(portraitHeightKey, _portrait);
    }
    if (_landscape !=
        (prefs.getDouble(landscapeHeightKey) ?? defaultHeight)) {
      await prefs.setDouble(landscapeHeightKey, _landscape);
    }
  }

  double _sanitize(double h) => h < minSaneKeyboardHeight ? defaultHeight : h;

  /// Height for the current orientation (never below [defaultHeight] floor
  /// used for keyboard-panel sizing when store was poisoned).
  double heightFor({required bool landscape}) {
    final raw = landscape ? _landscape : _portrait;
    return raw < minSaneKeyboardHeight ? defaultHeight : raw;
  }

  /// Records a settled IME height.
  ///
  /// Never shrinks a sane stored height from a single sample — hide-animation
  /// frames were poisoning the keyboard-panel target.
  Future<void> record(double height, {required bool landscape}) async {
    if (height < minSaneKeyboardHeight) {
      return;
    }
    final prefs = _prefs;
    if (landscape) {
      if (height + 1 < _landscape && _landscape >= minSaneKeyboardHeight) {
        return;
      }
      if (_landscape == height) return;
      _landscape = height;
      await prefs?.setDouble(landscapeHeightKey, height);
    } else {
      if (height + 1 < _portrait && _portrait >= minSaneKeyboardHeight) {
        return;
      }
      if (_portrait == height) return;
      _portrait = height;
      await prefs?.setDouble(portraitHeightKey, height);
    }
  }

  /// Persists the selected type tab.
  Future<void> setSelectedPage(int page) async {
    if (_selectedPage == page) return;
    _selectedPage = page;
    await _prefs?.setInt(selectedPageKey, page);
  }
}
