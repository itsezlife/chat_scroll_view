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
export 'src/controller/bulletin_controller.dart';
export 'src/desktop/desktop_bulletin_builders.dart';
export 'src/ios/bulletin_countdown_ios.dart';
export 'src/ios/bulletin_ios.dart';
export 'src/policy/bulletin_policy.dart';
export 'src/view/bulletin_builders.dart';
export 'src/view/bulletin_card.dart';
export 'src/view/bulletin_host.dart';
export 'src/view/bulletin_message.dart';
