#import "StarlightRuntimeBridge.h"

#import "StarlightAudio.h"
#import "StarlightHaptics.h"
#import "StarlightInput.h"
#import "StarlightPaths.h"
#import "StarlightPlatform.h"

#include <atomic>
#include <string>

@implementation StarlightRuntimeBridge
{
  std::atomic_bool _running;
}

+ (instancetype)shared
{
  static StarlightRuntimeBridge* instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [StarlightRuntimeBridge new];
  });
  return instance;
}

- (instancetype)init
{
  self = [super init];
  if (self)
    _running.store(false, std::memory_order_relaxed);
  return self;
}

- (BOOL)isAvailable
{
#if STARLIGHT_LINK_RUNTIME
  return YES;
#else
  return NO;
#endif
}

- (BOOL)isRunning
{
  return _running.load(std::memory_order_acquire);
}

- (BOOL)startWithLayer:(CAMetalLayer*)layer
{
#if STARLIGHT_LINK_RUNTIME
  if ([self isRunning])
    return YES;

  StarlightPaths* paths = StarlightPaths.shared;
  NSURL* gameSource = [paths selectedGameSource];
  if (!gameSource)
    return NO;

  std::string gamePath = gameSource.fileSystemRepresentation;
  std::string userPath = paths.user.fileSystemRepresentation;
  std::string texturePath = paths.textures.fileSystemRepresentation;
  CAMetalLayer* retainedLayer = layer;
  _running.store(true, std::memory_order_release);
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
    StarlightRuntimeHost host = {
        .game_path = gamePath.c_str(),
        .user_path = userPath.c_str(),
        .texture_path = texturePath.c_str(),
        .metal_layer = (__bridge void*)retainedLayer,
        .read_input = starlight_platform_read_input,
        .write_audio = starlight_platform_write_audio,
        .play_haptic = starlight_platform_play_haptic,
    };
    starlight_runtime_start(&host);
    self->_running.store(false, std::memory_order_release);
  });
  return YES;
#else
  (void)layer;
  return NO;
#endif
}

- (void)stop
{
#if STARLIGHT_LINK_RUNTIME
  if ([self isRunning])
    starlight_runtime_stop();
#endif
}

- (void)setPaused:(BOOL)paused
{
#if STARLIGHT_LINK_RUNTIME
  if ([self isRunning])
    starlight_runtime_pause(paused);
#else
  (void)paused;
#endif
}

- (void)resizeOutput:(CGSize)output render:(CGSize)render
{
#if STARLIGHT_LINK_RUNTIME
  if ([self isRunning])
  {
    starlight_runtime_resize(static_cast<uint32_t>(output.width),
                             static_cast<uint32_t>(output.height),
                             static_cast<uint32_t>(render.width),
                             static_cast<uint32_t>(render.height));
  }
#else
  (void)output;
  (void)render;
#endif
}

@end

extern "C" StarlightInputState starlight_platform_read_input(void)
{
  return [StarlightInput.shared snapshot];
}

extern "C" uint32_t starlight_platform_write_audio(const float* samples, uint32_t frames)
{
  return [StarlightAudio.shared writeInterleavedStereo:samples frames:frames];
}

extern "C" void starlight_platform_play_haptic(float intensity, float duration_seconds)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [StarlightHaptics.shared playIntensity:intensity duration:duration_seconds];
  });
}
