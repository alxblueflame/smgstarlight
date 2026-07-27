#import "StarlightInput.h"

#import "StarlightSettings.h"

#import <CoreMotion/CoreMotion.h>
#import <GameController/GameController.h>
#import <os/lock.h>

#include <array>

namespace
{
struct TouchButtonSpec
{
  CGPoint center;
  CGFloat radius;
  uint32_t button;
  const char* label;
};

std::array<TouchButtonSpec, 7> GetTouchButtons(CGRect bounds, UIEdgeInsets safe, CGFloat unit)
{
  const CGFloat right = bounds.size.width - safe.right;
  const CGFloat bottom = bounds.size.height - safe.bottom;
  return {{
      {{right - unit * 0.80, bottom - unit * 1.15}, unit * 0.42, STARLIGHT_BUTTON_A, "A"},
      {{right - unit * 1.78, bottom - unit * 0.78}, unit * 0.36, STARLIGHT_BUTTON_B, "B"},
      {{right - unit * 1.43, bottom - unit * 1.92}, unit * 0.38, STARLIGHT_BUTTON_SPIN, "SPIN"},
      {{right - unit * 2.62, bottom - unit * 0.72}, unit * 0.32, STARLIGHT_BUTTON_Z, "Z"},
      {{right - unit * 2.70, bottom - unit * 1.55}, unit * 0.32, STARLIGHT_BUTTON_C, "C"},
      {{bounds.size.width * 0.46, safe.top + unit * 0.48}, unit * 0.25,
       STARLIGHT_BUTTON_MINUS, "−"},
      {{bounds.size.width * 0.54, safe.top + unit * 0.48}, unit * 0.25,
       STARLIGHT_BUTTON_PLUS, "+"},
  }};
}
}

@implementation StarlightInput
{
  os_unfair_lock _lock;
  StarlightInputState _state;
  CMMotionManager* _motion;
  GCController* _activeController;
  id _connectObserver;
  id _disconnectObserver;
}

+ (instancetype)shared
{
  static StarlightInput* instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [StarlightInput new];
  });
  return instance;
}

- (instancetype)init
{
  self = [super init];
  if (self)
  {
    _lock = OS_UNFAIR_LOCK_INIT;
    _state = {};
  }
  return self;
}

- (void)start
{
  __weak StarlightInput* weakSelf = self;
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  _connectObserver = [center addObserverForName:GCControllerDidConnectNotification
                                         object:nil
                                          queue:NSOperationQueue.mainQueue
                                     usingBlock:^(NSNotification* note) {
                                       [weakSelf bindController:note.object];
                                     }];
  _disconnectObserver = [center addObserverForName:GCControllerDidDisconnectNotification
                                            object:nil
                                             queue:NSOperationQueue.mainQueue
                                        usingBlock:^(NSNotification*) {
                                          [weakSelf bindController:GCController.controllers.firstObject];
                                        }];
  [self bindController:GCController.controllers.firstObject];

  _motion = [CMMotionManager new];
  if (StarlightSettings.shared.gyroEnabled && _motion.deviceMotionAvailable)
  {
    _motion.deviceMotionUpdateInterval = 1.0 / 120.0;
    [_motion startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical];
  }

  if (@available(iOS 14.0, *))
  {
    GCKeyboard.coalescedKeyboard.keyboardInput.keyChangedHandler =
        ^(GCKeyboardInput*, GCControllerButtonInput*, GCKeyCode code, BOOL pressed) {
          [weakSelf handleKey:code pressed:pressed];
        };
    GCMouse.current.mouseInput.mouseMovedHandler = ^(GCMouseInput*, float x, float y) {
      [weakSelf addPointerX:x * 0.01f y:-y * 0.01f];
    };
    GCMouse.current.mouseInput.leftButton.pressedChangedHandler =
        ^(GCControllerButtonInput*, float, BOOL pressed) {
          [weakSelf setTouchButton:STARLIGHT_BUTTON_A pressed:pressed];
        };
    GCMouse.current.mouseInput.rightButton.pressedChangedHandler =
        ^(GCControllerButtonInput*, float, BOOL pressed) {
          [weakSelf setTouchButton:STARLIGHT_BUTTON_B pressed:pressed];
        };
  }
}

- (void)stop
{
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  if (_connectObserver)
    [center removeObserver:_connectObserver];
  if (_disconnectObserver)
    [center removeObserver:_disconnectObserver];
  [_motion stopDeviceMotionUpdates];
  _activeController.extendedGamepad.valueChangedHandler = nil;
  _activeController = nil;
}

- (void)bindController:(GCController*)controller
{
  _activeController.extendedGamepad.valueChangedHandler = nil;
  _activeController = controller;
  __weak StarlightInput* weakSelf = self;
  controller.extendedGamepad.valueChangedHandler =
      ^(GCExtendedGamepad* pad, GCControllerElement*) {
        [weakSelf updateFromGamepad:pad];
      };
}

- (void)updateFromGamepad:(GCExtendedGamepad*)pad
{
  os_unfair_lock_lock(&_lock);
  _state.move_x = pad.leftThumbstick.xAxis.value;
  _state.move_y = pad.leftThumbstick.yAxis.value;
  _state.pointer_x = pad.rightThumbstick.xAxis.value;
  _state.pointer_y = pad.rightThumbstick.yAxis.value;

  const uint32_t mask = STARLIGHT_BUTTON_A | STARLIGHT_BUTTON_B | STARLIGHT_BUTTON_Z |
                        STARLIGHT_BUTTON_C | STARLIGHT_BUTTON_SPIN | STARLIGHT_BUTTON_PLUS |
                        STARLIGHT_BUTTON_MINUS | STARLIGHT_BUTTON_DPAD_UP |
                        STARLIGHT_BUTTON_DPAD_DOWN | STARLIGHT_BUTTON_DPAD_LEFT |
                        STARLIGHT_BUTTON_DPAD_RIGHT;
  _state.buttons &= ~mask;
  if (pad.buttonA.pressed)
    _state.buttons |= STARLIGHT_BUTTON_A;
  if (pad.rightTrigger.pressed)
    _state.buttons |= STARLIGHT_BUTTON_B;
  if (pad.leftTrigger.pressed)
    _state.buttons |= STARLIGHT_BUTTON_Z;
  if (pad.leftShoulder.pressed)
    _state.buttons |= STARLIGHT_BUTTON_C;
  if (pad.buttonX.pressed)
    _state.buttons |= STARLIGHT_BUTTON_SPIN;
  if (pad.buttonMenu.pressed)
    _state.buttons |= STARLIGHT_BUTTON_PLUS;
  if (pad.buttonOptions.pressed)
    _state.buttons |= STARLIGHT_BUTTON_MINUS;
  if (pad.dpad.up.pressed)
    _state.buttons |= STARLIGHT_BUTTON_DPAD_UP;
  if (pad.dpad.down.pressed)
    _state.buttons |= STARLIGHT_BUTTON_DPAD_DOWN;
  if (pad.dpad.left.pressed)
    _state.buttons |= STARLIGHT_BUTTON_DPAD_LEFT;
  if (pad.dpad.right.pressed)
    _state.buttons |= STARLIGHT_BUTTON_DPAD_RIGHT;
  os_unfair_lock_unlock(&_lock);
}

- (void)handleKey:(GCKeyCode)code pressed:(BOOL)pressed API_AVAILABLE(ios(14.0))
{
  uint32_t button = 0;
  if (code == GCKeyCodeSpacebar)
    button = STARLIGHT_BUTTON_A;
  else if (code == GCKeyCodeLeftShift)
    button = STARLIGHT_BUTTON_B;
  else if (code == GCKeyCodeKeyE)
    button = STARLIGHT_BUTTON_SPIN;
  else if (code == GCKeyCodeEscape)
    button = STARLIGHT_BUTTON_PLUS;
  if (button)
    [self setTouchButton:button pressed:pressed];

  os_unfair_lock_lock(&_lock);
  const float value = pressed ? 1.0f : 0.0f;
  if (code == GCKeyCodeKeyW)
    _state.move_y = value;
  else if (code == GCKeyCodeKeyS)
    _state.move_y = -value;
  else if (code == GCKeyCodeKeyA)
    _state.move_x = -value;
  else if (code == GCKeyCodeKeyD)
    _state.move_x = value;
  os_unfair_lock_unlock(&_lock);
}

- (void)addPointerX:(float)x y:(float)y
{
  os_unfair_lock_lock(&_lock);
  _state.pointer_x = MAX(-1.0f, MIN(1.0f, _state.pointer_x + x));
  _state.pointer_y = MAX(-1.0f, MIN(1.0f, _state.pointer_y + y));
  os_unfair_lock_unlock(&_lock);
}

- (StarlightInputState)snapshot
{
  os_unfair_lock_lock(&_lock);
  if (StarlightSettings.shared.gyroEnabled)
  {
    GCMotion* controllerMotion = _activeController.motion;
    if (controllerMotion)
    {
      _state.gyro_x = controllerMotion.rotationRate.x;
      _state.gyro_y = controllerMotion.rotationRate.y;
      _state.gyro_z = controllerMotion.rotationRate.z;
    }
    else if (_motion.deviceMotion)
    {
      _state.gyro_x = _motion.deviceMotion.rotationRate.x;
      _state.gyro_y = _motion.deviceMotion.rotationRate.y;
      _state.gyro_z = _motion.deviceMotion.rotationRate.z;
    }
  }
  StarlightInputState copy = _state;
  os_unfair_lock_unlock(&_lock);
  return copy;
}

- (void)setTouchMoveX:(float)x y:(float)y
{
  os_unfair_lock_lock(&_lock);
  _state.move_x = MAX(-1.0f, MIN(1.0f, x));
  _state.move_y = MAX(-1.0f, MIN(1.0f, y));
  os_unfair_lock_unlock(&_lock);
}

- (void)setTouchPointerX:(float)x y:(float)y
{
  os_unfair_lock_lock(&_lock);
  _state.pointer_x = MAX(-1.0f, MIN(1.0f, x));
  _state.pointer_y = MAX(-1.0f, MIN(1.0f, y));
  os_unfair_lock_unlock(&_lock);
}

- (void)setTouchButton:(uint32_t)button pressed:(BOOL)pressed
{
  os_unfair_lock_lock(&_lock);
  if (pressed)
    _state.buttons |= button;
  else
    _state.buttons &= ~button;
  os_unfair_lock_unlock(&_lock);
}

@end

@implementation StarlightTouchOverlay
{
  NSMutableDictionary<NSValue*, NSNumber*>* _roles;
  CGPoint _moveOrigin;
  id _connectObserver;
  id _disconnectObserver;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self)
  {
    self.multipleTouchEnabled = YES;
    self.userInteractionEnabled = YES;
    self.backgroundColor = UIColor.clearColor;
    _roles = [NSMutableDictionary dictionary];
    __weak StarlightTouchOverlay* weakSelf = self;
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    _connectObserver = [center addObserverForName:GCControllerDidConnectNotification
                                           object:nil
                                            queue:NSOperationQueue.mainQueue
                                       usingBlock:^(NSNotification*) {
                                         [weakSelf setNeedsLayout];
                                       }];
    _disconnectObserver = [center addObserverForName:GCControllerDidDisconnectNotification
                                              object:nil
                                               queue:NSOperationQueue.mainQueue
                                          usingBlock:^(NSNotification*) {
                                            [weakSelf setNeedsLayout];
                                          }];
  }
  return self;
}

- (void)dealloc
{
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  if (_connectObserver)
    [center removeObserver:_connectObserver];
  if (_disconnectObserver)
    [center removeObserver:_disconnectObserver];
}

- (void)drawRect:(CGRect)rect
{
  if (!StarlightSettings.shared.touchControlsEnabled || GCController.controllers.count > 0)
    return;

  CGContextRef context = UIGraphicsGetCurrentContext();
  UIColor* fill = [UIColor colorWithWhite:1.0 alpha:0.16];
  UIColor* stroke = [UIColor colorWithWhite:1.0 alpha:0.55];
  CGContextSetFillColorWithColor(context, fill.CGColor);
  CGContextSetStrokeColorWithColor(context, stroke.CGColor);
  CGContextSetLineWidth(context, 2.0);

  const UIEdgeInsets safe = self.safeAreaInsets;
  const CGFloat unit = MIN(rect.size.width, rect.size.height) * 0.14;
  CGRect stick = CGRectMake(safe.left + unit * 0.4, rect.size.height - safe.bottom - unit * 2.2,
                           unit * 1.8, unit * 1.8);
  CGContextFillEllipseInRect(context, stick);
  CGContextStrokeEllipseInRect(context, stick);

  NSMutableParagraphStyle* paragraph = [NSMutableParagraphStyle new];
  paragraph.alignment = NSTextAlignmentCenter;
  NSDictionary* attributes = @{
    NSFontAttributeName : [UIFont boldSystemFontOfSize:MAX(10.0, unit * 0.17)],
    NSForegroundColorAttributeName : [UIColor colorWithWhite:1.0 alpha:0.88],
    NSParagraphStyleAttributeName : paragraph,
  };
  for (const TouchButtonSpec& spec : GetTouchButtons(rect, safe, unit))
  {
    CGRect button = CGRectMake(spec.center.x - spec.radius, spec.center.y - spec.radius,
                               spec.radius * 2.0, spec.radius * 2.0);
    CGContextFillEllipseInRect(context, button);
    CGContextStrokeEllipseInRect(context, button);
    NSString* label = [NSString stringWithUTF8String:spec.label];
    const CGFloat labelHeight = unit * 0.28;
    CGRect labelRect = CGRectMake(button.origin.x, spec.center.y - labelHeight * 0.5,
                                  button.size.width, labelHeight);
    [label drawInRect:labelRect withAttributes:attributes];
  }
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  self.hidden = !StarlightSettings.shared.touchControlsEnabled || GCController.controllers.count > 0;
  [self setNeedsDisplay];
}

- (uint32_t)buttonAtPoint:(CGPoint)point
{
  const UIEdgeInsets safe = self.safeAreaInsets;
  const CGFloat unit = MIN(self.bounds.size.width, self.bounds.size.height) * 0.14;
  for (const TouchButtonSpec& spec : GetTouchButtons(self.bounds, safe, unit))
  {
    if (hypot(point.x - spec.center.x, point.y - spec.center.y) < spec.radius * 1.35)
      return spec.button;
  }
  return 0;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  for (UITouch* touch in touches)
  {
    CGPoint point = [touch locationInView:self];
    NSValue* key = [NSValue valueWithNonretainedObject:touch];
    if (point.x < self.bounds.size.width * 0.38)
    {
      _roles[key] = @(-1);
      _moveOrigin = point;
    }
    else
    {
      uint32_t button = [self buttonAtPoint:point];
      if (button)
      {
        _roles[key] = @(button);
        [StarlightInput.shared setTouchButton:button pressed:YES];
      }
      else
      {
        _roles[key] = @(-2);
      }
    }
  }
  [self touchesMoved:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  for (UITouch* touch in touches)
  {
    NSNumber* role = _roles[[NSValue valueWithNonretainedObject:touch]];
    CGPoint point = [touch locationInView:self];
    if (role.integerValue == -1)
    {
      const CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) * 0.1;
      [StarlightInput.shared setTouchMoveX:(point.x - _moveOrigin.x) / radius
                                         y:(_moveOrigin.y - point.y) / radius];
    }
    else if (role.integerValue == -2)
    {
      [StarlightInput.shared setTouchPointerX:point.x / self.bounds.size.width * 2.0 - 1.0
                                           y:1.0 - point.y / self.bounds.size.height * 2.0];
    }
  }
  (void)event;
}

- (void)endTouches:(NSSet<UITouch*>*)touches
{
  for (UITouch* touch in touches)
  {
    NSValue* key = [NSValue valueWithNonretainedObject:touch];
    NSNumber* role = _roles[key];
    if (role.integerValue == -1)
      [StarlightInput.shared setTouchMoveX:0 y:0];
    else if (role.integerValue > 0)
      [StarlightInput.shared setTouchButton:role.unsignedIntValue pressed:NO];
    [_roles removeObjectForKey:key];
  }
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  [self endTouches:touches];
  (void)event;
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  [self endTouches:touches];
  (void)event;
}

@end
