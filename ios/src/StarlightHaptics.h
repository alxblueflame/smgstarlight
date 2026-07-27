#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StarlightHaptics : NSObject

+ (instancetype)shared;
- (void)start;
- (void)stop;
- (void)playIntensity:(float)intensity duration:(NSTimeInterval)duration;

@end

NS_ASSUME_NONNULL_END
