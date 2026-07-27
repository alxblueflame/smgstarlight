#import "StarlightHaptics.h"

#import "StarlightSettings.h"

#import <CoreHaptics/CoreHaptics.h>

@implementation StarlightHaptics
{
  CHHapticEngine* _engine;
}

+ (instancetype)shared
{
  static StarlightHaptics* instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [StarlightHaptics new];
  });
  return instance;
}

- (void)start
{
  if (!StarlightSettings.shared.hapticsEnabled ||
      !CHHapticEngine.capabilitiesForHardware.supportsHaptics)
    return;

  NSError* error;
  _engine = [[CHHapticEngine alloc] initAndReturnError:&error];
  if (!_engine || error)
    return;

  __weak StarlightHaptics* weakSelf = self;
  _engine.resetHandler = ^{
    [weakSelf->_engine startAndReturnError:nil];
  };
  [_engine startAndReturnError:nil];
}

- (void)stop
{
  [_engine stopWithCompletionHandler:nil];
  _engine = nil;
}

- (void)playIntensity:(float)intensity duration:(NSTimeInterval)duration
{
  if (!_engine || !StarlightSettings.shared.hapticsEnabled)
    return;

  CHHapticEventParameter* strength =
      [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity
                                                   value:MAX(0.0f, MIN(intensity, 1.0f))];
  CHHapticEventParameter* sharpness =
      [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness
                                                   value:0.45f];
  CHHapticEventType type =
      duration <= 0.03 ? CHHapticEventTypeHapticTransient : CHHapticEventTypeHapticContinuous;
  CHHapticEvent* event = [[CHHapticEvent alloc] initWithEventType:type
                                                      parameters:@[ strength, sharpness ]
                                                    relativeTime:0.0
                                                        duration:MAX(0.0, duration)];
  CHHapticPattern* pattern = [[CHHapticPattern alloc] initWithEvents:@[ event ]
                                                         parameters:@[]
                                                              error:nil];
  id<CHHapticPatternPlayer> player = [_engine createPlayerWithPattern:pattern error:nil];
  [player startAtTime:0 error:nil];
}

@end
