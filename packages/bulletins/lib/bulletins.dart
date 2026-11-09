/// Bulletins: short notices shown over a surface for a few seconds, with an
/// optional Undo or button.
///
/// A host makes one `BulletinController` per surface, mounts it with a
/// `BulletinHost` over the surface's content, and shows a `Bulletin` through
/// it. Colours come from `BulletinTokens` and labels from `BulletinStrings`
/// in `chrome_foundation`.
library;

export 'src/bulletin/bulletin.dart';
export 'src/controller/bulletin_clock.dart';
export 'src/policy/bulletin_policy.dart';
