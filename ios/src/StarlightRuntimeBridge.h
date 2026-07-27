#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

NS_ASSUME_NONNULL_BEGIN

@interface StarlightRuntimeBridge : NSObject

@property(nonatomic, readonly, getter=isAvailable) BOOL available;
@property(nonatomic, readonly, getter=isRunning) BOOL running;

+ (instancetype)shared;
- (BOOL)startWithLayer:(CAMetalLayer*)layer;
- (void)stop;
- (void)setPaused:(BOOL)paused;
- (void)resizeOutput:(CGSize)output render:(CGSize)render;

@end

NS_ASSUME_NONNULL_END
