#import "StarlightSettings.h"

NSNotificationName const StarlightSettingsDidChangeNotification =
    @"StarlightSettingsDidChangeNotification";

@implementation StarlightSettings

+ (instancetype)shared
{
  static StarlightSettings* instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [StarlightSettings new];
    [instance load];
  });
  return instance;
}

- (void)load
{
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  [defaults registerDefaults:@{
    @"suspendInBackground" : @YES,
    @"preventIdleSleep" : @YES,
    @"touchControlsEnabled" : @YES,
    @"gyroEnabled" : @YES,
    @"hapticsEnabled" : @YES,
    @"hdrEnabled" : @NO,
    @"metalFXEnabled" : @YES,
    @"preferredFrameRate" : @60,
    @"minimumResolutionScale" : @0.5f,
    @"maximumResolutionScale" : @1.0f,
  }];
  self.suspendInBackground = [defaults boolForKey:@"suspendInBackground"];
  self.preventIdleSleep = [defaults boolForKey:@"preventIdleSleep"];
  self.touchControlsEnabled = [defaults boolForKey:@"touchControlsEnabled"];
  self.gyroEnabled = [defaults boolForKey:@"gyroEnabled"];
  self.hapticsEnabled = [defaults boolForKey:@"hapticsEnabled"];
  self.hdrEnabled = [defaults boolForKey:@"hdrEnabled"];
  self.metalFXEnabled = [defaults boolForKey:@"metalFXEnabled"];
  self.preferredFrameRate = [defaults integerForKey:@"preferredFrameRate"];
  self.minimumResolutionScale = [defaults floatForKey:@"minimumResolutionScale"];
  self.maximumResolutionScale = [defaults floatForKey:@"maximumResolutionScale"];
}

- (void)save
{
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  [defaults setBool:self.suspendInBackground forKey:@"suspendInBackground"];
  [defaults setBool:self.preventIdleSleep forKey:@"preventIdleSleep"];
  [defaults setBool:self.touchControlsEnabled forKey:@"touchControlsEnabled"];
  [defaults setBool:self.gyroEnabled forKey:@"gyroEnabled"];
  [defaults setBool:self.hapticsEnabled forKey:@"hapticsEnabled"];
  [defaults setBool:self.hdrEnabled forKey:@"hdrEnabled"];
  [defaults setBool:self.metalFXEnabled forKey:@"metalFXEnabled"];
  [defaults setInteger:self.preferredFrameRate forKey:@"preferredFrameRate"];
  [defaults setFloat:self.minimumResolutionScale forKey:@"minimumResolutionScale"];
  [defaults setFloat:self.maximumResolutionScale forKey:@"maximumResolutionScale"];
}

@end
