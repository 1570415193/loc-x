#import <UIKit/UIKit.h>
#import <NetworkExtension/NetworkExtension.h>
NSString *RunRules(NSString *command,BOOL *success){*success=NO;return @"Simulator helper disabled";}
int run_rules_command(const char *command){return 64;}
@interface Home:UIViewController
- (void)startProxyForOperation:(NSUInteger)op;
@end
@interface TestHome:Home
@end
@implementation TestHome
- (NSError *)certificateError{return nil;}
- (void)refresh{}
@end
@interface FakeConnection:NSObject
@property NSUInteger starts;
@property NSDictionary *options;
@property BOOL reject;
@end
@implementation FakeConnection
- (NEVPNStatus)status{return NEVPNStatusDisconnected;}
- (BOOL)startTunnelWithOptions:(NSDictionary *)options andReturnError:(NSError **)error{self.starts++;self.options=options;if(self.reject&&error)*error=[NSError errorWithDomain:NEVPNErrorDomain code:NEVPNErrorConfigurationDisabled userInfo:nil];return !self.reject;}
@end
@interface FakeManager:NETunnelProviderManager
@property NSUInteger saves,loads;
@property FakeConnection *fake;
@end
@implementation FakeManager
- (NEVPNConnection *)connection{return (id)self.fake;}
- (void)saveToPreferencesWithCompletionHandler:(void (^)(NSError *))handler{self.saves++;handler(nil);}
- (void)loadFromPreferencesWithCompletionHandler:(void (^)(NSError *))handler{self.loads++;handler(nil);}
@end
static TestHome *Make(BOOL configured,BOOL enabled,BOOL reject){TestHome *h=[TestHome new];FakeManager *m=[FakeManager new];m.fake=[FakeConnection new];m.fake.reject=reject;m.enabled=enabled;if(configured){NETunnelProviderProtocol *p=[NETunnelProviderProtocol new];p.providerBundleIdentifier=@"local.wloc.standalone.tunnel";p.providerConfiguration=@{@"latitude":@1,@"longitude":@2};m.protocolConfiguration=p;}[h setValue:m forKey:@"manager"];[h setValue:@{@"latitude":@31.23,@"longitude":@121.47} forKey:@"pendingTarget"];[h setValue:@1 forKey:@"operation"];[h startProxyForOperation:1];return h;}
@interface ReuseObserver:NSObject
@end
@implementation ReuseObserver
+ (void)load{[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){static BOOL once=NO;if(once)return;once=YES;TestHome *existing=Make(YES,YES,NO),*fresh=Make(NO,NO,NO),*disabled=Make(YES,NO,NO),*rejected=Make(YES,YES,YES);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{NSMutableDictionary *r=[NSMutableDictionary dictionary];FakeManager *a=[existing valueForKey:@"manager"],*b=[fresh valueForKey:@"manager"],*c=[disabled valueForKey:@"manager"],*d=[rejected valueForKey:@"manager"];r[@"existingConfigNotSavedAgain"]=@(a.saves==0);r[@"existingReceivesCurrentTarget"]=@([a.fake.options[@"target"]isEqual:[existing valueForKey:@"pendingTarget"]]);r[@"freshConfigSavedOnce"]=@(b.saves==1&&b.fake.starts==1);r[@"disabledPromptsWithoutSave"]=@(c.saves==0&&[[disabled valueForKey:@"phase"]isEqual:@"manual"]);r[@"rejectedPromptsWithoutSave"]=@(d.saves==0&&[[rejected valueForKey:@"phase"]isEqual:@"manual"]);NSString *dir=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;[[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingPrettyPrinted error:nil]writeToFile:[dir stringByAppendingPathComponent:@"layout.json"] atomically:YES];});}];}
@end
