#import <TargetConditionals.h>

#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

/// The iOS and macOS texture host of ADR 043: a `FlutterTexture` per texture
/// over a ring of IOSurface-backed `CVPixelBuffer`s, kept by texture id so a
/// render worker locks and posts it through `frame_texture_lock` and
/// `frame_texture_post` (the ABI of `native/include/frame_texture.h`, defined
/// in `FrameTexturePlugin.m`).
///
/// The channel has two methods, both on the platform thread: `create`
/// (`{width, height}`) answers the texture id, or null when the platform
/// cannot make one; `destroy` (the id) ends it.
@interface FrameTexturePlugin : NSObject <FlutterPlugin>
@end
