#import <Foundation/Foundation.h>
#import "LocationFix.h"
static CLLocation *Fix(double lat,double lon,double accuracy,NSDate *date){return [[CLLocation alloc]initWithCoordinate:(CLLocationCoordinate2D){lat,lon} altitude:0 horizontalAccuracy:accuracy verticalAccuracy:1 timestamp:date];}
int main(){@autoreleasepool{NSDate *now=[NSDate dateWithTimeIntervalSince1970:1700000000];
 NSCAssert(WLOCUsableLocation(Fix(0,0,25,now),now),@"zero valid");
 NSCAssert(WLOCUsableLocation(Fix(31.23,121.47,3000,[now dateByAddingTimeInterval:-5]),now),@"fresh coarse fix valid");
 NSCAssert(!WLOCUsableLocation(Fix(31.23,121.47,25,[now dateByAddingTimeInterval:-31]),now),@"stale fix rejected");
 NSCAssert(!WLOCUsableLocation(Fix(31.23,121.47,25,[now dateByAddingTimeInterval:6]),now),@"future fix rejected");
 NSCAssert(!WLOCUsableLocation(Fix(91,121.47,25,now),now),@"invalid latitude rejected");
 NSCAssert(!WLOCUsableLocation(Fix(31.23,121.47,-1,now),now),@"invalid accuracy rejected");
 NSCAssert(!WLOCUsableLocation(nil,now),@"missing fix rejected");
 puts("PASS production location validation: fresh/coarse/zero fixes accepted, stale/future/invalid fixes rejected");}}
