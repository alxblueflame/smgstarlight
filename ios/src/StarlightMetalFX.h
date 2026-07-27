#import <Metal/Metal.h>

NS_ASSUME_NONNULL_BEGIN

@interface StarlightMetalFX : NSObject

@property(nonatomic, readonly) BOOL supported;

- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (BOOL)configureInputSize:(MTLSize)inputSize
                outputSize:(MTLSize)outputSize
               pixelFormat:(MTLPixelFormat)pixelFormat;
- (void)invalidate;
- (BOOL)encodeSpatialUpscale:(id<MTLCommandBuffer>)commandBuffer
                      source:(id<MTLTexture>)source
                 destination:(id<MTLTexture>)destination;

@end

NS_ASSUME_NONNULL_END
