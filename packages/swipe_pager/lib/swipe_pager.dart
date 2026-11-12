/// A horizontal pager whose swipe claims the gesture only past a slop and a
/// direction rule: a page's vertical scrollables and nested horizontal
/// scrollers keep their drags. Settle physics, programmatic paging, a host
/// chosen keep-alive policy, right-to-left, semantics and keyboard paging.
///
/// Depends on the Flutter SDK only.
library;

export 'src/swipe_pager.dart';
export 'src/swipe_pager_keep_alive.dart';
export 'src/swipe_pager_physics.dart';
