#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol StarlightMetalViewDelegate <NSObject>
- (void)metalViewOutputSizeChanged:(CGSize)outputSize renderSize:(CGSize)renderSize;
@end

@interface StarlightMetalView : UIView

@property(nonatomic, weak) id<StarlightMetalViewDelegate> delegate;
@property(nonatomic, readonly) CAMetalLayer* metalLayer;
@property(nonatomic, readonly) CGSize outputSize;
@property(nonatomic, readonly) CGSize renderSize;

- (void)configureDisplay;
- (void)submitGpuTimeMilliseconds:(double)milliseconds;

@end

NS_ASSUME_NONNULL_END
