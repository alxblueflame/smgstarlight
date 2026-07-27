#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StarlightAudio : NSObject

+ (instancetype)shared;
- (BOOL)start:(NSError**)error;
- (void)stop;
- (uint32_t)writeInterleavedStereo:(const float*)samples frames:(uint32_t)frames;

@end

NS_ASSUME_NONNULL_END
