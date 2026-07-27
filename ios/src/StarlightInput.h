#import <UIKit/UIKit.h>

#include "StarlightPlatform.h"

NS_ASSUME_NONNULL_BEGIN

@interface StarlightInput : NSObject

+ (instancetype)shared;
- (void)start;
- (void)stop;
- (StarlightInputState)snapshot;
- (void)setTouchMoveX:(float)x y:(float)y;
- (void)setTouchPointerX:(float)x y:(float)y;
- (void)setTouchButton:(uint32_t)button pressed:(BOOL)pressed;

@end

@interface StarlightTouchOverlay : UIView
@end

NS_ASSUME_NONNULL_END
