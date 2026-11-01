import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/widget/patterned_fill.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Slug [leftHalf] is registered under.
const patternSlug = 'half';

/// Square artwork, opaque on its left half only. Cover-fit into the 800 × 600
/// test view it spans 800 × 800, so the view's left half lies inside the
/// pattern and its right half outside.
const leftHalf = SvgStringLoader('''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <rect x="0" y="0" width="50" height="100" fill="#FF0000"/>
</svg>''');

/// [child] under a [size] (800 × 600 by default) [MediaQuery] and a [ChatWallpaperPatterns]
/// registry of [artwork].
Widget patternsHost(
  Widget child, {
  Map<String, BytesLoader> artwork = const {patternSlug: leftHalf},
  double devicePixelRatio = 1,
  bool disableAnimations = false,
  Size size = const Size(800, 600),
}) => MediaQuery(
  data: MediaQueryData(
    size: size,
    devicePixelRatio: devicePixelRatio,
    disableAnimations: disableAnimations,
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: ChatWallpaperPatterns(artwork: artwork, child: child),
  ),
);

/// Whether a wallpaper view in the tree composites a pattern over its fill.
bool composited(WidgetTester tester) =>
    find.byKey(PatternedFill.compositeKey).evaluate().isNotEmpty;

/// Delivers the engine's async work (SVG parsing, rasterizing) until [done],
/// for at most [steps] rounds.
Future<void> deliver(
  WidgetTester tester, {
  bool Function()? done,
  int steps = 50,
}) async {
  for (var step = 0; step < steps && !(done?.call() ?? false); step++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}

/// [deliver] until [done], failing if it never holds.
Future<void> settle(WidgetTester tester, bool Function() done) async {
  await deliver(tester, done: done);
  expect(done(), isTrue, reason: 'async work did not land');
}

/// Empties the image cache, live images included; for `tearDown`, since
/// every test resolving a raster leaves it cached.
void clearImageCache() => PaintingBinding.instance.imageCache
  ..clear()
  ..clearLiveImages();

/// The display every pattern test runs on unless it sets its own: a portrait
/// 600 × 1000 physical pixels, so patterns rasterize 600 px wide.
const testDisplay = Size(600, 1000);

TestDisplay get _display =>
    TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!.display;

/// Puts the test view on [testDisplay]; for `setUp`, paired with
/// [resetDisplay].
void pinDisplay() => _display.size = testDisplay;

/// Gives the test view its default display back; for `tearDown`.
void resetDisplay() => _display.reset();
