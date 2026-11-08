#import <UIKit/UIKit.h>
#import "MapPanel.h"
NSString *RunRules(NSString *command,BOOL *success){*success=NO;return @"Simulator: production helper is disabled";}
int run_rules_command(const char *command){return 64;}
@interface Home:UIViewController
- (void)modify; - (void)selectLatitude:(double)lat longitude:(double)lon;
- (NSError *)certificateError;
- (void)becameActive; - (BOOL)restartRequired; - (void)recordRestartRequired;
- (void)checkRulesForOperation:(NSUInteger)op;
- (void)receiveStatus:(NSDictionary *)status operation:(NSUInteger)op;
@end
@interface TestHome:Home
@property BOOL trusted,checkOK,wrongTarget;
@property NSString *fixture;
@property NSUInteger starts,writes;
@end
@implementation TestHome
- (BOOL)connectionIsReady{return YES;}
- (BOOL)restartRequired{return NO;}
- (void)recordRestartRequired{}
- (NSError *)certificateError{return self.trusted?nil:[NSError errorWithDomain:@"test untrusted" code:1 userInfo:nil];}
- (void)loadManagerForOperation:(NSUInteger)op{[self checkRulesForOperation:op];}
- (void)executeRules:(NSString *)command completion:(void (^)(BOOL,NSString *))completion{if([command isEqual:@"check"])completion(self.checkOK,self.fixture);else{self.writes++;completion(YES,@"Applied. Restart iPhone to validate with trustd.");}}
- (void)startProxyForOperation:(NSUInteger)op{self.starts++;[self setValue:@"connecting" forKey:@"phase"];NSDictionary *t=self.wrongTarget?@{@"latitude":@1,@"longitude":@2}:[self valueForKey:@"pendingTarget"];[self receiveStatus:@{@"controlAPI":@1,@"ready":@YES,@"target":t,@"patched":@0,@"failures":@0} operation:op];}
@end
static BOOL Phase(Home *h,NSString *s){return [[h valueForKey:@"phase"]isEqual:s];}
@interface LayoutObserver:NSObject
@end
@implementation LayoutObserver
+ (void)load{[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification){static BOOL ran=NO;if(ran)return;ran=YES;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
 UIWindow *window=UIApplication.sharedApplication.windows.firstObject;TestHome *h=[TestHome new];window.rootViewController=[[UINavigationController alloc]initWithRootViewController:h];[window layoutIfNeeded];NSMutableDictionary *r=[NSMutableDictionary dictionary];h.checkOK=YES;h.trusted=YES;h.fixture=@"Target rule: absent\nCompatibility: target-absent";
 [h setValue:nil forKey:@"target"];[h modify];r[@"selectionRequired"]=@(![[h valueForKey:@"busy"]boolValue]&&h.starts==0);
 [h selectLatitude:31.23 longitude:121.47];h.trusted=NO;[h modify];r[@"manualTrustRequired"]=@(Phase(h,@"certificate")&&h.starts==0);h.trusted=YES;[h becameActive];r[@"returnsFromSettingsAndResumes"]=@(Phase(h,@"success")&&h.starts==1);h.checkOK=NO;[h modify];r[@"failedCheckBlocksProxy"]=@(Phase(h,@"failed")&&h.starts==1);
 h.checkOK=YES;[h modify];r[@"absentSkipsWriteAndStarts"]=@(Phase(h,@"success")&&h.starts==2&&h.writes==0);
 h.fixture=@"Target rule: present\nCompatibility: policy-format-unknown";[h modify];r[@"unknownRuleRefused"]=@(Phase(h,@"failed")&&h.writes==0);
 h.fixture=@"Target rule: present\nCompatibility: v131-local-baseline";[h modify];r[@"ruleWriteRequiresRestart"]=@(Phase(h,@"failed")&&h.writes==1&&h.starts==2);
 h.fixture=@"Target rule: absent\nCompatibility: target-absent";h.wrongTarget=YES;[h modify];r[@"wrongTargetCannotSucceed"]=@(Phase(h,@"failed"));h.wrongTarget=NO;
 NSUInteger op=[[h valueForKey:@"operation"]unsignedIntegerValue];[h selectLatitude:31.24 longitude:121.48];[h receiveStatus:@{@"target":@{@"latitude":@31.23,@"longitude":@121.47},@"patched":@99} operation:op];r[@"staleReplyIgnored"]=@(Phase(h,@"idle"));
 Home *real=[Home new];r[@"actualSystemTrustNotAssumed"]=@([real certificateError]!=nil);[real recordRestartRequired];r[@"restartGatePersists"]=@([real restartRequired]);[NSUserDefaults.standardUserDefaults removeObjectForKey:@"rulesRestartBoot"];
 __block void (^poll)(NSUInteger);__weak TestHome *weakHome=h;
 poll=^(NSUInteger remaining){TestHome *home=weakHome;MapPanel *panel=[home valueForKey:@"map"];if(!panel.tilesVisible&&remaining){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{poll(remaining-1);});return;}
 r[@"liveTilesVisible"]=@(panel.tilesVisible);
 [panel.web evaluateJavaScript:@"const d=toDisplay(31.2304,121.4737); map.fire('click',{latlng:L.latLng(d.lat,d.lon)}); ({tiles:loaded,pin:!!marker,zoom:map.getZoom()})" completionHandler:^(id value,NSError *error){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{NSDictionary *target=[home valueForKey:@"target"];r[@"webMapTapSelectsWGS84"]=@(!error&&[value[@"pin"]boolValue]&&fabs([target[@"latitude"]doubleValue]-31.2304)<1e-8&&fabs([target[@"longitude"]doubleValue]-121.4737)<1e-8);NSString *dir=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;[[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[dir stringByAppendingPathComponent:@"layout.json"] atomically:YES];poll=nil;});}];};poll(38);
 });}];}
@end
