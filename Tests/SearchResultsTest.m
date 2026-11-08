#import <Foundation/Foundation.h>
#import "SearchResults.h"
@interface TestPlace:NSObject
@property CLLocation *location;
@property NSString *name,*administrativeArea,*locality,*subLocality,*thoroughfare;
@end
@implementation TestPlace
@end
int main(){@autoreleasepool{
 TestPlace *a=[TestPlace new];a.location=[[CLLocation alloc]initWithLatitude:31.2304 longitude:121.4737];a.name=@"人民广场";a.locality=@"上海";a.administrativeArea=@"上海";TestPlace *missing=[TestPlace new];TestPlace *bad=[TestPlace new];bad.location=[[CLLocation alloc]initWithLatitude:91 longitude:0];
 NSArray *items=WLOCSearchResults((id)@[missing,bad,a]);NSCAssert(items.count==1,@"invalid results filtered");NSDictionary *first=items.firstObject;NSCAssert([first[@"latitude"]doubleValue]==31.2304&&[first[@"longitude"]doubleValue]==121.4737,@"coordinates preserved without extra offset");NSCAssert([first[@"name"]isEqual:@"人民广场"]&&[first[@"address"]isEqual:@"上海"],@"name and deduplicated address");NSMutableArray *many=[NSMutableArray array];for(int i=0;i<12;i++)[many addObject:a];NSCAssert(WLOCSearchResults(many).count==8,@"result limit");puts("PASS production search result mapping: valid coordinates preserved, missing/invalid results filtered, address and result limit");}}
