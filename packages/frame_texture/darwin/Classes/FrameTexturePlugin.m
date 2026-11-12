/*
 * The Apple texture host of ADR 043 (iOS and macOS share this file).
 *
 * A texture is a FlutterTexture over a CVPixelBufferPool of IOSurface-backed
 * BGRA buffers, at most kBuffersPerTexture of them out at once: the ring. A
 * lock takes a buffer of the pool and locks its base address; a post unlocks
 * it and makes it the newest, which copyPixelBuffer hands the engine on the
 * raster thread. A buffer goes back to the pool only when every holder let go
 * of it (this texture, the engine's last frame, the Metal texture made from
 * it), so a writer never gets a buffer the engine still reads. A pool with
 * every buffer out refuses at once (the allocation threshold): the lock
 * answers NULL and the worker skips that frame.
 *
 * Threads. The worker's lock and post may run on any thread; the table and
 * each texture hold their os_unfair_lock only around bookkeeping, never
 * across a CoreVideo call, so no caller waits on another one's lock or post.
 * textureFrameAvailable must be called on the platform thread: on both iOS
 * and macOS it ends in Shell::OnPlatformViewMarkTextureFrameAvailable, which
 * checks that it runs on the platform task runner (the main thread). A post
 * therefore sends one signal to the main queue per texture, coalesced: posts
 * made before the main thread runs it share it.
 */
#import "FrameTexturePlugin.h"

#import <CoreVideo/CoreVideo.h>
#import <os/lock.h>
#include <stdint.h>

/* The buffers a texture holds in steady state: the newest posted one (which
 * the engine may also hold as its last frame), the one the engine drew before
 * it while the GPU may still read it, and the one the worker writes.
 * PlatformFrameTextureHost.appleBuffersPerTexture counts the same. */
static const int kBuffersPerTexture = 3;

#define FRAME_TEXTURE_EXPORT __attribute__((visibility("default"), used))

/* ---- The worker's ABI (native/include/frame_texture.h) ---- */

FRAME_TEXTURE_EXPORT void* frame_texture_lock(int64_t id, int32_t* row_stride);
FRAME_TEXTURE_EXPORT void frame_texture_post(int64_t id);
FRAME_TEXTURE_EXPORT int32_t frame_texture_count(void);

typedef NS_ENUM(NSInteger, FTLockState) {
  /* No buffer is out to a writer. */
  FTLockStateIdle,
  /* A caller is between taking the texture and CoreVideo returning. */
  FTLockStateBusy,
  /* A buffer is out to a writer, its base address locked. */
  FTLockStateLocked,
};

/* One texture: its pool, the buffer out to the writer and the newest posted
 * one. */
@interface FTRingTexture : NSObject <FlutterTexture>
- (nullable instancetype)initWithWidth:(int32_t)width
                                height:(int32_t)height
                              registry:(NSObject<FlutterTextureRegistry>*)registry;
@property(nonatomic) int64_t textureId;
/* The first byte of a free buffer, its row stride written to *rowStride; NULL
 * when destroyed, already locked or locking, or every buffer is out. */
- (void*)lockWithRowStride:(int32_t*)rowStride;
/* Makes the locked buffer the newest and signals the engine. YES when the
 * texture was destroyed and its last lock has now ended. */
- (BOOL)post;
/* Destroyed, and no lock in progress: nothing will lock or post it again. */
@property(nonatomic, readonly) BOOL ended;
/* Ends the texture (platform thread). YES when no lock is in progress, so
 * nothing will post it again. */
- (BOOL)destroy;
/* Frees the pool's buffers that nobody holds. */
- (void)trim;
@end

/* ---- The table: textures by id, for the worker's ABI ---- */

static os_unfair_lock gTableLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSNumber*, FTRingTexture*>* gTable;

static FTRingTexture* FTFind(int64_t textureId) {
  os_unfair_lock_lock(&gTableLock);
  FTRingTexture* texture = gTable[@(textureId)];
  os_unfair_lock_unlock(&gTableLock);
  return texture;
}

static void FTAdd(FTRingTexture* texture) {
  os_unfair_lock_lock(&gTableLock);
  if (gTable == nil) gTable = [NSMutableDictionary dictionary];
  gTable[@(texture.textureId)] = texture;
  os_unfair_lock_unlock(&gTableLock);
}

static void FTRemove(FTRingTexture* texture) {
  os_unfair_lock_lock(&gTableLock);
  NSNumber* key = @(texture.textureId);
  if (gTable[key] == texture) [gTable removeObjectForKey:key];
  os_unfair_lock_unlock(&gTableLock);
}

static NSArray<FTRingTexture*>* FTAll(void) {
  os_unfair_lock_lock(&gTableLock);
  NSArray<FTRingTexture*>* all = gTable.allValues ?: @[];
  os_unfair_lock_unlock(&gTableLock);
  return all;
}

void* frame_texture_lock(int64_t id, int32_t* row_stride) {
  if (row_stride == NULL) return NULL;
  @autoreleasepool {
    FTRingTexture* texture = FTFind(id);
    if (texture == nil) return NULL;
    void* bits = [texture lockWithRowStride:row_stride];
    // A lock that failed after a destroy may have been the last one.
    if (bits == NULL && texture.ended) FTRemove(texture);
    return bits;
  }
}

void frame_texture_post(int64_t id) {
  @autoreleasepool {
    FTRingTexture* texture = FTFind(id);
    if (texture != nil && [texture post]) FTRemove(texture);
  }
}

int32_t frame_texture_count(void) {
  os_unfair_lock_lock(&gTableLock);
  int32_t count = (int32_t)gTable.count;
  os_unfair_lock_unlock(&gTableLock);
  return count;
}

/* ---- One texture ---- */

@implementation FTRingTexture {
  int32_t _width;
  int32_t _height;
  CVPixelBufferPoolRef _pool;
  NSDictionary* _allocation;
  __weak NSObject<FlutterTextureRegistry>* _registry;

  /* Guards everything below. */
  os_unfair_lock _lock;
  FTLockState _state;
  CVPixelBufferRef _locked;
  CVPixelBufferRef _newest;
  BOOL _destroyed;
  BOOL _signalPending;
}

- (nullable instancetype)initWithWidth:(int32_t)width
                                height:(int32_t)height
                              registry:(NSObject<FlutterTextureRegistry>*)registry {
  if (self = [super init]) {
    _width = width;
    _height = height;
    _registry = registry;
    _lock = OS_UNFAIR_LOCK_INIT;
    NSDictionary* buffers = @{
      (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
      (id)kCVPixelBufferWidthKey : @(width),
      (id)kCVPixelBufferHeightKey : @(height),
      (id)kCVPixelBufferIOSurfacePropertiesKey : @{},
      (id)kCVPixelBufferMetalCompatibilityKey : @YES,
    };
    if (CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)buffers,
                                &_pool) != kCVReturnSuccess) {
      return nil;
    }
    _allocation = @{(id)kCVPixelBufferPoolAllocationThresholdKey : @(kBuffersPerTexture)};
  }
  return self;
}

- (void)dealloc {
  CVPixelBufferRelease(_newest);
  if (_locked != NULL) {
    CVPixelBufferUnlockBaseAddress(_locked, 0);
    CVPixelBufferRelease(_locked);
  }
  CVPixelBufferPoolRelease(_pool);
}

- (void*)lockWithRowStride:(int32_t*)rowStride {
  os_unfair_lock_lock(&_lock);
  if (_destroyed || _state != FTLockStateIdle) {
    os_unfair_lock_unlock(&_lock);
    return NULL;
  }
  _state = FTLockStateBusy;
  os_unfair_lock_unlock(&_lock);

  CVPixelBufferRef buffer = NULL;
  CVReturn status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
      kCFAllocatorDefault, _pool, (__bridge CFDictionaryRef)_allocation, &buffer);
  void* bits = NULL;
  size_t stride = 0;
  if (status == kCVReturnSuccess && buffer != NULL) {
    if (CVPixelBufferLockBaseAddress(buffer, 0) == kCVReturnSuccess) {
      bits = CVPixelBufferGetBaseAddress(buffer);
      stride = CVPixelBufferGetBytesPerRow(buffer);
      if (bits == NULL || CVPixelBufferGetWidth(buffer) < (size_t)_width ||
          CVPixelBufferGetHeight(buffer) < (size_t)_height || stride < (size_t)_width * 4 ||
          stride > INT32_MAX) {
        CVPixelBufferUnlockBaseAddress(buffer, 0);
        bits = NULL;
      }
    }
    if (bits == NULL) {
      CVPixelBufferRelease(buffer);
      buffer = NULL;
    }
  }

  os_unfair_lock_lock(&_lock);
  if (buffer == NULL) {
    // Every buffer is out (the threshold), or CoreVideo refused.
    _state = FTLockStateIdle;
  } else {
    _locked = buffer;
    _state = FTLockStateLocked;
  }
  os_unfair_lock_unlock(&_lock);
  if (bits != NULL) *rowStride = (int32_t)stride;
  return bits;
}

- (BOOL)ended {
  os_unfair_lock_lock(&_lock);
  BOOL ended = _destroyed && _state == FTLockStateIdle;
  os_unfair_lock_unlock(&_lock);
  return ended;
}

- (BOOL)post {
  os_unfair_lock_lock(&_lock);
  if (_state != FTLockStateLocked) {
    os_unfair_lock_unlock(&_lock);
    return NO;
  }
  CVPixelBufferRef buffer = _locked;
  _locked = NULL;
  _state = FTLockStateBusy;
  os_unfair_lock_unlock(&_lock);

  CVPixelBufferUnlockBaseAddress(buffer, 0);

  os_unfair_lock_lock(&_lock);
  CVPixelBufferRef previous = NULL;
  BOOL destroyed = _destroyed;
  BOOL signal = NO;
  if (destroyed) {
    // Nobody shows it any more.
    previous = buffer;
  } else {
    previous = _newest;
    _newest = buffer;
    signal = !_signalPending;
    _signalPending = YES;
  }
  _state = FTLockStateIdle;
  os_unfair_lock_unlock(&_lock);

  CVPixelBufferRelease(previous);
  if (signal) {
    // The platform thread only (see the top of the file).
    dispatch_async(dispatch_get_main_queue(), ^{
      [self signalFrame];
    });
  }
  return destroyed;
}

- (void)signalFrame {
  os_unfair_lock_lock(&_lock);
  _signalPending = NO;
  BOOL destroyed = _destroyed;
  os_unfair_lock_unlock(&_lock);
  // destroy runs on this thread too, so no signal follows an unregister.
  if (!destroyed) [_registry textureFrameAvailable:_textureId];
}

- (BOOL)destroy {
  os_unfair_lock_lock(&_lock);
  if (_destroyed) {
    os_unfair_lock_unlock(&_lock);
    return NO;
  }
  _destroyed = YES;
  BOOL idle = _state == FTLockStateIdle;
  CVPixelBufferRef newest = _newest;
  _newest = NULL;
  os_unfair_lock_unlock(&_lock);
  CVPixelBufferRelease(newest);
  [_registry unregisterTexture:_textureId];
  return idle;
}

- (void)trim {
  CVPixelBufferPoolFlush(_pool, kCVPixelBufferPoolFlushExcessBuffers);
}

/* The raster thread: the newest posted buffer, retained for the engine, or
 * NULL before the first post (the engine then keeps what it had). */
- (CVPixelBufferRef _Nullable)copyPixelBuffer {
  os_unfair_lock_lock(&_lock);
  CVPixelBufferRef buffer = _newest == NULL ? NULL : CVPixelBufferRetain(_newest);
  os_unfair_lock_unlock(&_lock);
  return buffer;
}

@end

/* ---- The plugin ---- */

@implementation FrameTexturePlugin {
  NSObject<FlutterTextureRegistry>* _textures;
  /* The ids this engine made, to end them when it goes. */
  NSMutableSet<NSNumber*>* _ids;
  dispatch_source_t _memoryPressure;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FrameTexturePlugin* plugin = [[FrameTexturePlugin alloc] initWithTextures:[registrar textures]];
  FlutterMethodChannel* channel =
      [FlutterMethodChannel methodChannelWithName:@"dev.chatscrollview.frame_texture"
                                  binaryMessenger:[registrar messenger]];
  [registrar addMethodCallDelegate:plugin channel:channel];
}

- (instancetype)initWithTextures:(NSObject<FlutterTextureRegistry>*)textures {
  if (self = [super init]) {
    _textures = textures;
    _ids = [NSMutableSet set];
    // Under memory pressure every texture gives back the buffers nobody
    // holds; the pool above destroys its idle textures through the scope.
    _memoryPressure = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
        DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL,
        dispatch_get_main_queue());
    dispatch_source_set_event_handler(_memoryPressure, ^{
      for (FTRingTexture* texture in FTAll()) [texture trim];
    });
    dispatch_resume(_memoryPressure);
  }
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"create"]) {
    NSDictionary* arguments = call.arguments;
    NSNumber* width = [arguments isKindOfClass:[NSDictionary class]] ? arguments[@"width"] : nil;
    NSNumber* height = [arguments isKindOfClass:[NSDictionary class]] ? arguments[@"height"] : nil;
    if (![width isKindOfClass:[NSNumber class]] || ![height isKindOfClass:[NSNumber class]] ||
        width.intValue <= 0 || height.intValue <= 0) {
      result([FlutterError errorWithCode:@"bad_size"
                                 message:@"width and height must be positive"
                                 details:nil]);
      return;
    }
    result([self createWithWidth:width.intValue height:height.intValue]);
  } else if ([call.method isEqualToString:@"destroy"]) {
    if ([call.arguments isKindOfClass:[NSNumber class]]) {
      [self destroy:[call.arguments longLongValue]];
    }
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

/* The new texture's id, or nil when the platform refused one. */
- (NSNumber*)createWithWidth:(int32_t)width height:(int32_t)height {
  FTRingTexture* texture = [[FTRingTexture alloc] initWithWidth:width
                                                         height:height
                                                       registry:_textures];
  if (texture == nil) return nil;
  int64_t textureId = [_textures registerTexture:texture];
  if (textureId == 0) return nil;
  texture.textureId = textureId;
  FTAdd(texture);
  [_ids addObject:@(textureId)];
  return @(textureId);
}

- (void)destroy:(int64_t)textureId {
  if (![_ids containsObject:@(textureId)]) return;
  [_ids removeObject:@(textureId)];
  FTRingTexture* texture = FTFind(textureId);
  // A lock in progress keeps it in the table until its post.
  if (texture != nil && [texture destroy]) FTRemove(texture);
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  for (NSNumber* textureId in [_ids copy]) [self destroy:textureId.longLongValue];
  dispatch_source_cancel(_memoryPressure);
}

@end
