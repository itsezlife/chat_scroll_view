/// A viewport's user-driven scroll, for a host to choose: the **scroll
/// physics** (a fling paired with an edge effect, with a preset per platform
/// family) a viewport takes, and the keyboard scroll keys
/// ([ViewportScrollKeys]).
///
/// A viewport that runs these physics itself reads their runtime from
/// `package:viewport_scroll/engine.dart`.
///
/// Depends on the Flutter SDK only.
library;

export 'src/viewport_scroll_keys.dart';
export 'src/viewport_scroll_physics.dart'
    show
        ViewportEdgeEffect,
        ViewportEdgeEffect$None,
        ViewportEdgeEffect$RubberBand,
        ViewportEdgeEffect$Stretch,
        ViewportFling,
        ViewportFling$Decay,
        ViewportFling$Spline,
        ViewportScrollPhysics;
