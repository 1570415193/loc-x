#import <Foundation/Foundation.h>
#import "TargetSettings.h"
int main(){@autoreleasepool{
 NSDictionary *old=@{@"latitude":@1,@"longitude":@2},*last=@{@"latitude":@3,@"longitude":@4},*fresh=@{@"latitude":@31.23,@"longitude":@121.47};
 NSCAssert([WLOCInitialTarget(@{@"target":fresh},last,old)isEqual:fresh],@"explicit new target wins over stale configuration");
 NSCAssert([WLOCInitialTarget(nil,last,old)isEqual:last],@"manual connection uses last target");
 NSCAssert([WLOCInitialTarget(nil,nil,old)isEqual:old],@"legacy configuration remains supported");
 NSCAssert(WLOCInitialTarget(@{@"target":@{@"latitude":@99,@"longitude":@2}},last,old)==nil,@"invalid explicit option cannot select stale target");
 NSCAssert(WLOCValidatedTarget(@{@"latitude":@0,@"longitude":@0})!=nil,@"zero is valid");
 NSCAssert(WLOCValidatedTarget(@{@"latitude":@"31",@"longitude":@2})==nil,@"strings are invalid");
 puts("PASS production target selection: explicit options, manual resume, legacy fallback and invalid/zero values");
}}
