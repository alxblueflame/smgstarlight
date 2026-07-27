#import "StarlightPaths.h"

#include <cstring>

namespace
{
NSString* const StarlightPathErrorDomain = @"StarlightPathError";
NSString* const StarlightSelectedGameKey = @"selectedGameSource";

NSError* PathError(NSInteger code, NSString* message)
{
  return [NSError errorWithDomain:StarlightPathErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

BOOL IsRMGE01(const uint8_t* bytes)
{
  return std::memcmp(bytes, "RMGE01", 6) == 0;
}

BOOL ReadBytes(NSFileHandle* handle, uint64_t offset, NSUInteger length, NSData** data,
               NSError** error)
{
  if (![handle seekToOffset:offset error:error])
    return NO;
  NSData* value = [handle readDataUpToLength:length error:error];
  if (!value || value.length != length)
  {
    if (error && !*error)
      *error = PathError(3, @"The game image is truncated.");
    return NO;
  }
  *data = value;
  return YES;
}
}

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
    _gameRoot = [_root URLByAppendingPathComponent:@"Game" isDirectory:YES];
    _game = [_gameRoot URLByAppendingPathComponent:@"RMGE01" isDirectory:YES];
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
  for (NSURL* url in @[ self.gameRoot, self.game, self.saves, self.textures, self.cache ])
  {
    if (![manager createDirectoryAtURL:url
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:error])
      return NO;
  }
  NSArray<NSURL*>* gameFiles = [manager contentsOfDirectoryAtURL:self.gameRoot
                                       includingPropertiesForKeys:nil
                                                          options:0
                                                            error:nil];
  for (NSURL* url in gameFiles)
  {
    if ([url.lastPathComponent hasPrefix:@".import-"])
      [manager removeItemAtURL:url error:nil];
  }
  return [self.cache setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:error];
}

- (NSURL*)selectedGameSource
{
  NSFileManager* manager = NSFileManager.defaultManager;
  NSString* selected = [NSUserDefaults.standardUserDefaults stringForKey:StarlightSelectedGameKey];
  if (selected.length)
  {
    NSURL* candidate = [self.gameRoot URLByAppendingPathComponent:selected];
    if ([self validateGameSource:candidate error:nil])
      return candidate;
  }

  NSURL* dol = [self.game URLByAppendingPathComponent:@"sys/main.dol"];
  if ([manager fileExistsAtPath:dol.path])
    return self.game;

  NSArray<NSURL*>* files = [manager contentsOfDirectoryAtURL:self.gameRoot
                                  includingPropertiesForKeys:nil
                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                       error:nil];
  for (NSURL* candidate in files)
  {
    if ([self validateGameSource:candidate error:nil])
    {
      [NSUserDefaults.standardUserDefaults setObject:candidate.lastPathComponent
                                              forKey:StarlightSelectedGameKey];
      return candidate;
    }
  }
  return nil;
}

- (BOOL)validateGameSource:(NSURL*)url error:(NSError**)error
{
  NSString* extension = url.pathExtension.lowercaseString;
  if (![extension isEqualToString:@"iso"] && ![extension isEqualToString:@"wbfs"])
  {
    if (error)
      *error = PathError(1, @"Choose an ISO or WBFS file.");
    return NO;
  }

  NSError* openError;
  NSFileHandle* handle = [NSFileHandle fileHandleForReadingFromURL:url error:&openError];
  if (!handle)
  {
    if (error)
      *error = openError ?: PathError(2, @"The game image could not be opened.");
    return NO;
  }

  NSData* header;
  BOOL valid = NO;
  if (ReadBytes(handle, 0, 32, &header, &openError))
  {
    const uint8_t* bytes = static_cast<const uint8_t*>(header.bytes);
    if ([extension isEqualToString:@"iso"])
    {
      const uint32_t magic = (static_cast<uint32_t>(bytes[24]) << 24) |
                             (static_cast<uint32_t>(bytes[25]) << 16) |
                             (static_cast<uint32_t>(bytes[26]) << 8) | bytes[27];
      valid = IsRMGE01(bytes) && magic == 0x5D1C9EA3;
    }
    else if (std::memcmp(bytes, "WBFS", 4) == 0)
    {
      const uint8_t hdSectorShift = bytes[8];
      const uint8_t wbfsSectorShift = bytes[9];
      if (hdSectorShift >= 9 && hdSectorShift <= 31 && wbfsSectorShift >= 15 &&
          wbfsSectorShift <= 31 && bytes[12] != 0)
      {
        NSData* discHeader;
        const uint64_t offset = 1ULL << hdSectorShift;
        if (ReadBytes(handle, offset, 6, &discHeader, &openError))
          valid = IsRMGE01(static_cast<const uint8_t*>(discHeader.bytes));
      }
    }
  }
  [handle closeFile];

  if (!valid && error)
  {
    *error = openError ?: PathError(
                                 4, @"This is not a valid USA Super Mario Galaxy (RMGE01) image.");
  }
  return valid;
}

- (NSURL*)importGameSource:(NSURL*)url error:(NSError**)error
{
  const BOOL accessing = [url startAccessingSecurityScopedResource];
  @try
  {
    if (![self validateGameSource:url error:error])
      return nil;

    NSNumber* sourceSize;
    if (![url getResourceValue:&sourceSize forKey:NSURLFileSizeKey error:error])
      return nil;

    NSNumber* available;
    if (![self.gameRoot getResourceValue:&available
                                  forKey:NSURLVolumeAvailableCapacityForImportantUsageKey
                                   error:error])
      return nil;
    if (available.longLongValue < sourceSize.longLongValue + 64 * 1024 * 1024)
    {
      if (error)
        *error = PathError(5, @"There is not enough free storage to import this game image.");
      return nil;
    }

    NSString* base = url.URLByDeletingPathExtension.lastPathComponent;
    NSString* extension = url.pathExtension.lowercaseString;
    NSURL* destination =
        [self.gameRoot URLByAppendingPathComponent:[base stringByAppendingPathExtension:extension]];
    NSUInteger suffix = 2;
    while ([NSFileManager.defaultManager fileExistsAtPath:destination.path])
    {
      NSString* name = [NSString stringWithFormat:@"%@-%lu", base, (unsigned long)suffix++];
      destination = [self.gameRoot
          URLByAppendingPathComponent:[name stringByAppendingPathExtension:extension]];
    }

    NSString* temporaryName =
        [[NSString stringWithFormat:@".import-%@", NSUUID.UUID.UUIDString]
            stringByAppendingPathExtension:extension];
    NSURL* temporary = [self.gameRoot URLByAppendingPathComponent:temporaryName];
    if (![NSFileManager.defaultManager copyItemAtURL:url toURL:temporary error:error])
    {
      [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
      return nil;
    }
    if (![self validateGameSource:temporary error:error])
    {
      [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
      return nil;
    }
    if (![NSFileManager.defaultManager moveItemAtURL:temporary toURL:destination error:error])
    {
      [NSFileManager.defaultManager removeItemAtURL:temporary error:nil];
      return nil;
    }

    [NSUserDefaults.standardUserDefaults setObject:destination.lastPathComponent
                                            forKey:StarlightSelectedGameKey];
    return destination;
  }
  @finally
  {
    if (accessing)
      [url stopAccessingSecurityScopedResource];
  }
}

@end
