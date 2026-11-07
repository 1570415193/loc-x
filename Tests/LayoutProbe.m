#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
NSString *RunRules(NSString *command,BOOL *success){*success=NO;return @"Simulator: rules helper disabled";}
int run_rules_command(const char *command){return 64;}
@interface Home:UIViewController
@end
static void Walk(UIView *v,NSMutableArray *out){
 if([v isKindOfClass:UIButton.class]){UIButton *b=(id)v;[out addObject:@{@"kind":@"button",@"title":b.configuration.title?:b.currentTitle?:@"",@"height":@(v.bounds.size.height),@"width":@(v.bounds.size.width)}];}
 if([v isKindOfClass:UISearchBar.class])[out addObject:@{@"kind":@"search",@"height":@(v.bounds.size.height)}];
 if([v isKindOfClass:MKMapView.class])[out addObject:@{@"kind":@"map",@"height":@(v.bounds.size.height),@"width":@(v.bounds.size.width),@"latitudeSpan":@(((MKMapView *)v).region.span.latitudeDelta),@"longitudeSpan":@(((MKMapView *)v).region.span.longitudeDelta)}];
 if([v isKindOfClass:UIButton.class]||[v isKindOfClass:MKMapView.class]||[v isKindOfClass:UISearchBar.class])return;
 for(UIView *child in v.subviews)Walk(child,out);
}
@interface LayoutObserver:NSObject
@end
@implementation LayoutObserver
+ (void)load{[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{UIWindow *window=UIApplication.sharedApplication.windows.firstObject;[window layoutIfNeeded];NSMutableArray *views=[NSMutableArray array];Walk(window,views);NSData *data=[NSJSONSerialization dataWithJSONObject:views options:NSJSONWritingPrettyPrinted error:nil];NSString *dir=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;[data writeToFile:[dir stringByAppendingPathComponent:@"layout.json"] atomically:YES];NSLog(@"[WLOC-UI-REGRESSION] %@",views);});}];}
@end
