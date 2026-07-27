#import "StarlightMetalFX.h"

#import <MetalFX/MetalFX.h>

@implementation StarlightMetalFX
{
  id<MTLDevice> _device;
  id<MTLFXSpatialScaler> _spatial;
  MTLSize _inputSize;
  MTLSize _outputSize;
  MTLPixelFormat _pixelFormat;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
{
  self = [super init];
  if (self)
    _device = device;
  return self;
}

- (BOOL)supported
{
  return _device != nil && [MTLFXSpatialScalerDescriptor supportsDevice:_device];
}

- (BOOL)configureInputSize:(MTLSize)inputSize
                outputSize:(MTLSize)outputSize
               pixelFormat:(MTLPixelFormat)pixelFormat
{
  if (!self.supported || inputSize.width == 0 || inputSize.height == 0 ||
      outputSize.width == 0 || outputSize.height == 0)
    return NO;

  if (_spatial && _inputSize.width == inputSize.width && _inputSize.height == inputSize.height &&
      _outputSize.width == outputSize.width && _outputSize.height == outputSize.height &&
      _pixelFormat == pixelFormat)
    return YES;

  MTLFXSpatialScalerDescriptor* descriptor = [MTLFXSpatialScalerDescriptor new];
  descriptor.inputWidth = inputSize.width;
  descriptor.inputHeight = inputSize.height;
  descriptor.outputWidth = outputSize.width;
  descriptor.outputHeight = outputSize.height;
  descriptor.colorTextureFormat = pixelFormat;
  descriptor.outputTextureFormat = pixelFormat;
  descriptor.colorProcessingMode =
      pixelFormat == MTLPixelFormatRGBA16Float ? MTLFXSpatialScalerColorProcessingModeHDR :
                                                MTLFXSpatialScalerColorProcessingModePerceptual;
  _spatial = [descriptor newSpatialScalerWithDevice:_device];
  _inputSize = inputSize;
  _outputSize = outputSize;
  _pixelFormat = pixelFormat;
  return _spatial != nil;
}

- (void)invalidate
{
  _spatial = nil;
  _inputSize = MTLSizeMake(0, 0, 0);
  _outputSize = MTLSizeMake(0, 0, 0);
  _pixelFormat = MTLPixelFormatInvalid;
}

- (BOOL)encodeSpatialUpscale:(id<MTLCommandBuffer>)commandBuffer
                      source:(id<MTLTexture>)source
                 destination:(id<MTLTexture>)destination
{
  if (!_spatial || !commandBuffer || !source || !destination)
    return NO;
  _spatial.colorTexture = source;
  _spatial.inputContentWidth = source.width;
  _spatial.inputContentHeight = source.height;
  _spatial.outputTexture = destination;
  [_spatial encodeToCommandBuffer:commandBuffer];
  return YES;
}

@end
