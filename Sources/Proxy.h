#import <Foundation/Foundation.h>
@interface WLOCProxy : NSObject
- (instancetype)initWithSettings:(NSDictionary *)settings;
- (BOOL)start:(NSError **)error;
- (void)stop;
- (BOOL)updateSettings:(NSDictionary *)settings;
- (NSDictionary *)status;
@end
