#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const StarlightSettingsDidChangeNotification;

@interface StarlightSettings : NSObject

@property(nonatomic) BOOL suspendInBackground;
@property(nonatomic) BOOL preventIdleSleep;
@property(nonatomic) BOOL touchControlsEnabled;
@property(nonatomic) BOOL gyroEnabled;
@property(nonatomic) BOOL hapticsEnabled;
@property(nonatomic) BOOL hdrEnabled;
@property(nonatomic) BOOL metalFXEnabled;
@property(nonatomic) NSInteger preferredFrameRate;
@property(nonatomic) float minimumResolutionScale;
@property(nonatomic) float maximumResolutionScale;

+ (instancetype)shared;
- (void)save;

@end

NS_ASSUME_NONNULL_END
