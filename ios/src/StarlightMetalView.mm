#import "StarlightMetalView.h"

#import "StarlightDynamicResolution.h"
#import "StarlightMetalFX.h"
#import "StarlightSettings.h"

#import <Metal/Metal.h>

@implementation StarlightMetalView
{
  id<MTLDevice> _device;
  StarlightMetalFX* _metalFX;
  StarlightDynamicResolution _dynamicResolution;
  CGSize _outputSize;
  CGSize _renderSize;
}

+ (Class)layerClass
{
  return CAMetalLayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self)
  {
    self.backgroundColor = UIColor.blackColor;
    self.contentScaleFactor = UIScreen.mainScreen.nativeScale;
    _device = MTLCreateSystemDefaultDevice();
    _metalFX = [[StarlightMetalFX alloc] initWithDevice:_device];
    self.metalLayer.device = _device;
    self.metalLayer.framebufferOnly = NO;
    self.metalLayer.maximumDrawableCount = 3;
    self.metalLayer.presentsWithTransaction = NO;
    [self configureDisplay];
  }
  return self;
}

- (CAMetalLayer*)metalLayer
{
  return (CAMetalLayer*)self.layer;
}

- (CGSize)outputSize
{
  return _outputSize;
}

- (CGSize)renderSize
{
  return _renderSize;
}

- (void)configureDisplay
{
  StarlightSettings* settings = StarlightSettings.shared;
  _dynamicResolution.SetLimits(settings.minimumResolutionScale,
                               settings.maximumResolutionScale);
  _dynamicResolution.SetTargetFrameRate(static_cast<uint32_t>(settings.preferredFrameRate));

  if (settings.hdrEnabled && UIScreen.mainScreen.traitCollection.displayGamut == UIDisplayGamutP3)
  {
    self.metalLayer.wantsExtendedDynamicRangeContent = YES;
    self.metalLayer.pixelFormat = MTLPixelFormatRGBA16Float;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);
    self.metalLayer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
  }
  else
  {
    self.metalLayer.wantsExtendedDynamicRangeContent = NO;
    self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    self.metalLayer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
  }
  [self updateSizes];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  [self updateSizes];
}

- (void)didMoveToWindow
{
  [super didMoveToWindow];
  [self updateSizes];
}

- (void)updateSizes
{
  const CGFloat scale = self.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
  const CGSize bounds = self.bounds.size;
  CGSize output = {
      MAX(1.0, floor(bounds.width * scale)),
      MAX(1.0, floor(bounds.height * scale)),
  };
  const float resolutionScale = _dynamicResolution.GetScale();
  CGSize render = {
      MAX(1.0, floor(output.width * resolutionScale)),
      MAX(1.0, floor(output.height * resolutionScale)),
  };
  if (CGSizeEqualToSize(output, _outputSize) && CGSizeEqualToSize(render, _renderSize))
    return;

  _outputSize = output;
  _renderSize = render;
  self.metalLayer.contentsScale = scale;
  self.metalLayer.drawableSize = output;
  if (StarlightSettings.shared.metalFXEnabled)
  {
    [_metalFX configureInputSize:MTLSizeMake(render.width, render.height, 1)
                      outputSize:MTLSizeMake(output.width, output.height, 1)
                     pixelFormat:self.metalLayer.pixelFormat];
  }
  else
  {
    [_metalFX invalidate];
  }
  [self.delegate metalViewOutputSizeChanged:output renderSize:render];
}

- (void)submitGpuTimeMilliseconds:(double)milliseconds
{
  const float before = _dynamicResolution.GetScale();
  _dynamicResolution.SubmitGpuTime(milliseconds);
  if (_dynamicResolution.GetScale() != before)
    [self updateSizes];
}

@end
