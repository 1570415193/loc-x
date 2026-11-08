#import <CoreLocation/CoreLocation.h>
#import <math.h>
// Core Location geocoding returns CLLocation coordinates; keep these as WGS84.
// Only the map renderer converts WGS84 into the street basemap's display coordinates.
static inline NSArray<NSDictionary *> *WLOCSearchResults(NSArray<CLPlacemark *> *places){
 NSMutableArray *items=[NSMutableArray array];
 for(CLPlacemark *place in places){CLLocation *location=place.location;if(!location)continue;CLLocationCoordinate2D c=location.coordinate;if(!CLLocationCoordinate2DIsValid(c)||!isfinite(c.latitude)||!isfinite(c.longitude))continue;
 NSMutableArray *address=[NSMutableArray array];for(NSString *s in @[place.administrativeArea?:@"",place.locality?:@"",place.subLocality?:@"",place.thoroughfare?:@""])if(s.length&&![address containsObject:s])[address addObject:s];
 NSString *name=place.name.length?place.name:[address componentsJoinedByString:@" "];if(!name.length)name=@"搜索结果";
 [items addObject:@{@"name":name,@"address":[address componentsJoinedByString:@" "],@"latitude":@(c.latitude),@"longitude":@(c.longitude)}];if(items.count==8)break;}
 return items;
}
