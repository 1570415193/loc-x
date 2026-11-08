#import <Foundation/Foundation.h>
@interface WLOCProxy : NSObject
@property(nonatomic,copy) NSString *controlToken;
@property(nonatomic,copy) void (^sequenceDidChange)(NSNumber *sequence);
@property(nonatomic,copy) void (^targetDidChange)(NSDictionary *target);
@property(nonatomic) BOOL ready;
@property(nonatomic) unsigned long long controlSequence;
- (instancetype)initWithSettings:(NSDictionary *)settings;
- (BOOL)start:(NSError **)error;
- (void)stop;
- (BOOL)updateSettings:(NSDictionary *)settings;
- (NSDictionary *)status;
@end
