import 'package:panel_pages/src/bake/bake_activity_port.dart';

/// A [BakeActivityPort] that records what it was told and keeps motion as the
/// union over reporters, as a real baker does.
final class FakeBakeActivityPort implements BakeActivityPort {
  final _scrollers = <Object>{};

  /// Every `reportScrolling` call in order, as `(reporter, scrolling)`.
  final List<(Object reporter, bool scrolling)> reports = [];

  /// Every `prioritise` call in order.
  final List<List<String>> prioritised = [];

  /// Whether any reporter has reported that it is moving.
  bool get isScrolling => _scrollers.isNotEmpty;

  @override
  void reportScrolling({required Object reporter, required bool scrolling}) {
    reports.add((reporter, scrolling));
    if (scrolling) {
      _scrollers.add(reporter);
    } else {
      _scrollers.remove(reporter);
    }
  }

  @override
  void prioritise(List<String> glyphs) => prioritised.add(List.of(glyphs));
}
