#import "StarlightAudio.h"

#import <AVFAudio/AVFAudio.h>

#include <algorithm>
#include <atomic>
#include <vector>

namespace
{
constexpr uint32_t kSampleRate = 48000;
constexpr uint32_t kCapacityFrames = kSampleRate / 2;
}

@implementation StarlightAudio
{
  AVAudioEngine* _engine;
  AVAudioSourceNode* _source;
  std::vector<float> _ring;
  std::atomic<uint64_t> _readFrame;
  std::atomic<uint64_t> _writeFrame;
}

+ (instancetype)shared
{
  static StarlightAudio* instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [StarlightAudio new];
  });
  return instance;
}

- (instancetype)init
{
  self = [super init];
  if (self)
  {
    _ring.resize(static_cast<size_t>(kCapacityFrames) * 2);
    _readFrame.store(0, std::memory_order_relaxed);
    _writeFrame.store(0, std::memory_order_relaxed);
  }
  return self;
}

- (BOOL)start:(NSError**)error
{
  AVAudioSession* session = AVAudioSession.sharedInstance;
  if (![session setCategory:AVAudioSessionCategoryPlayback
                       mode:AVAudioSessionModeDefault
                    options:AVAudioSessionCategoryOptionAllowAirPlay |
                            AVAudioSessionCategoryOptionAllowBluetoothA2DP
                      error:error])
    return NO;
  if (![session setPreferredSampleRate:kSampleRate error:error])
    return NO;
  if (![session setPreferredIOBufferDuration:256.0 / kSampleRate error:error])
    return NO;
  if (![session setActive:YES error:error])
    return NO;

  _engine = [AVAudioEngine new];
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:kSampleRate
                                                                        channels:2];
  __weak StarlightAudio* weakSelf = self;
  _source = [[AVAudioSourceNode alloc]
      initWithFormat:format
         renderBlock:^OSStatus(BOOL* silence, const AudioTimeStamp*, AVAudioFrameCount frameCount,
                               AudioBufferList* outputData) {
           StarlightAudio* strongSelf = weakSelf;
           if (!strongSelf)
             return noErr;

           const uint64_t read = strongSelf->_readFrame.load(std::memory_order_relaxed);
           const uint64_t write = strongSelf->_writeFrame.load(std::memory_order_acquire);
           const uint32_t available =
               static_cast<uint32_t>(std::min<uint64_t>(write - read, frameCount));
           float* left = static_cast<float*>(outputData->mBuffers[0].mData);
           float* right = static_cast<float*>(outputData->mBuffers[1].mData);
           for (uint32_t frame = 0; frame < available; ++frame)
           {
             const size_t index = static_cast<size_t>((read + frame) % kCapacityFrames) * 2;
             left[frame] = strongSelf->_ring[index];
             right[frame] = strongSelf->_ring[index + 1];
           }
           if (available < frameCount)
           {
             std::fill(left + available, left + frameCount, 0.0f);
             std::fill(right + available, right + frameCount, 0.0f);
             *silence = available == 0;
           }
           strongSelf->_readFrame.store(read + available, std::memory_order_release);
           return noErr;
         }];

  [_engine attachNode:_source];
  [_engine connect:_source to:_engine.mainMixerNode format:format];
  return [_engine startAndReturnError:error];
}

- (void)stop
{
  [_engine stop];
  _source = nil;
  _engine = nil;
  _readFrame.store(0, std::memory_order_relaxed);
  _writeFrame.store(0, std::memory_order_relaxed);
  [AVAudioSession.sharedInstance setActive:NO
                               withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                     error:nil];
}

- (uint32_t)writeInterleavedStereo:(const float*)samples frames:(uint32_t)frames
{
  if (!samples || frames == 0)
    return 0;

  uint64_t write = _writeFrame.load(std::memory_order_relaxed);
  uint64_t read = _readFrame.load(std::memory_order_acquire);
  const uint32_t freeFrames =
      static_cast<uint32_t>(kCapacityFrames - std::min<uint64_t>(write - read, kCapacityFrames));
  const uint32_t count = std::min(frames, freeFrames);
  for (uint32_t frame = 0; frame < count; ++frame)
  {
    const size_t destination = static_cast<size_t>((write + frame) % kCapacityFrames) * 2;
    _ring[destination] = samples[frame * 2];
    _ring[destination + 1] = samples[frame * 2 + 1];
  }
  _writeFrame.store(write + count, std::memory_order_release);
  return count;
}

@end
