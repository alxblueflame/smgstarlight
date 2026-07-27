#import "StarlightPaths.h"

@implementation StarlightPaths

+ (instancetype)shared
{
  static StarlightPaths* instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [StarlightPaths new];
  });
  return instance;
}

- (instancetype)init
{
  self = [super init];
  if (self)
  {
    NSFileManager* manager = NSFileManager.defaultManager;
    NSURL* documents = [manager URLsForDirectory:NSDocumentDirectory
                                       inDomains:NSUserDomainMask].firstObject;
    NSURL* caches = [manager URLsForDirectory:NSCachesDirectory
                                    inDomains:NSUserDomainMask].firstObject;
    _root = [documents URLByAppendingPathComponent:@"Starlight" isDirectory:YES];
    _game = [_root URLByAppendingPathComponent:@"Game/RMGE01" isDirectory:YES];
    _user = [_root URLByAppendingPathComponent:@"User" isDirectory:YES];
    _saves = [_user URLByAppendingPathComponent:@"Wii/title/00010000/524d4745/data"
                                     isDirectory:YES];
    _textures = [_user URLByAppendingPathComponent:@"Load/Textures/RMGE01"
                                        isDirectory:YES];
    _cache = [caches URLByAppendingPathComponent:@"Starlight/RMGE01" isDirectory:YES];
  }
  return self;
}

- (BOOL)prepare:(NSError**)error
{
  NSFileManager* manager = NSFileManager.defaultManager;
  for (NSURL* url in @[ self.game, self.saves, self.textures, self.cache ])
  {
    if (![manager createDirectoryAtURL:url
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:error])
      return NO;
  }
  return [self.cache setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:error];
}

@end
