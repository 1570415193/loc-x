#import <CoreLocation/CoreLocation.h>
#import <math.h>
static inline BOOL WLOCUsableLocation(CLLocation *location,NSDate *now){
 if(!location||!CLLocationCoordinate2DIsValid(location.coordinate)||!isfinite(location.horizontalAccuracy)||location.horizontalAccuracy<0)return NO;
 NSTimeInterval age=[now timeIntervalSinceDate:location.timestamp];
 return isfinite(age)&&age>=-5&&age<=30;
}
