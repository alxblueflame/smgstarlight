#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StarlightPaths : NSObject

@property(nonatomic, readonly) NSURL* root;
@property(nonatomic, readonly) NSURL* game;
@property(nonatomic, readonly) NSURL* user;
@property(nonatomic, readonly) NSURL* saves;
@property(nonatomic, readonly) NSURL* textures;
@property(nonatomic, readonly) NSURL* cache;

+ (instancetype)shared;
- (BOOL)prepare:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
