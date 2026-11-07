#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <NetworkExtension/NetworkExtension.h>
#import <Security/Security.h>
#include "rules.h"
NSString *RunRules(NSString *command,BOOL *success);
@interface Home : UIViewController <MKMapViewDelegate,UISearchBarDelegate>
@property MKMapView *map;
@property UITextField *lat,*lon;
@property UITextView *log;
@property UILabel *state;
@property NETunnelProviderManager *manager;
@property NSMutableArray<UIButton *> *ruleButtons;
@property MKLocalSearch *search;
@property NSTimer *timer;
@end
@implementation Home
- (UIButton *)button:(NSString *)title action:(SEL)action{UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];b.configuration=[UIButtonConfiguration tintedButtonConfiguration];b.configuration.title=title;[b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;}
- (void)append:(NSString *)s{self.log.text=[NSString stringWithFormat:@"%@\n%@",s,self.log.text?:@""];}
- (UITextField *)field:(NSString *)hint{UITextField *f=[UITextField new];f.placeholder=hint;f.borderStyle=UITextBorderStyleRoundedRect;f.keyboardType=UIKeyboardTypeNumbersAndPunctuation;return f;}
- (void)viewDidLoad{[super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;self.title=@"WLOC 定位";
 UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];[NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
 UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];[NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],[stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-16]]];
 self.state=[UILabel new];self.state.numberOfLines=0;self.state.text=@"尚未启用 · 网络定位模式";[stack addArrangedSubview:self.state];UISearchBar *bar=[UISearchBar new];bar.placeholder=@"搜索地点";bar.delegate=self;[stack addArrangedSubview:bar];self.map=[MKMapView new];self.map.delegate=self;[self.map.heightAnchor constraintEqualToConstant:230].active=YES;[self.map addGestureRecognizer:[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(pick:)]];[stack addArrangedSubview:self.map];
 UILabel *help=[UILabel new];help.numberOfLines=0;help.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];help.text=@"长按地图选点，或输入 WGS84 经纬度。中国大陆地图选点按 GCJ-02 转换。效果取决于 WLOC 网络请求，不覆盖所有 GPS 结果。";[stack addArrangedSubview:help];self.lat=[self field:@"纬度 WGS84（-90～90）"];self.lon=[self field:@"经度 WGS84（-180～180）"];[stack addArrangedSubview:self.lat];[stack addArrangedSubview:self.lon];NSDictionary *saved=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"target"];if(saved){self.lat.text=[saved[@"latitude"]description];self.lon.text=[saved[@"longitude"]description];}
 [stack addArrangedSubview:[self button:@"应用位置" action:@selector(apply)]];[stack addArrangedSubview:[self button:@"恢复真实定位（停止代理）" action:@selector(stop)]];[stack addArrangedSubview:[self button:@"导出本机定位证书" action:@selector(certificate)]];
 UILabel *section=[UILabel new];section.text=@"规则维护 · 修改或恢复后需要重启";[stack addArrangedSubview:section];self.ruleButtons=[NSMutableArray array];NSArray *titles=@[@"检查规则（只读）",@"备份并应用 WLOC 规则修改",@"恢复原始证书规则"];NSArray *selectors=@[NSStringFromSelector(@selector(check)),NSStringFromSelector(@selector(change)),NSStringFromSelector(@selector(restore))];for(NSUInteger i=0;i<titles.count;i++){UIButton *b=[self button:titles[i] action:NSSelectorFromString(selectors[i])];[self.ruleButtons addObject:b];[stack addArrangedSubview:b];}
 self.log=[UITextView new];self.log.editable=NO;self.log.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];[self.log.heightAnchor constraintEqualToConstant:200].active=YES;[stack addArrangedSubview:self.log];[self append:@"首次使用：检查规则 → 导出并安装证书 → 在证书信任设置中手动信任 → 按需修改规则并重启 → 应用位置。不会自动修改规则或证书信任。"];
 [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error){dispatch_async(dispatch_get_main_queue(),^{for(NETunnelProviderManager *m in managers){if([((NETunnelProviderProtocol *)m.protocolConfiguration).providerBundleIdentifier isEqual:@"local.wloc.standalone.tunnel"]){self.manager=m;break;}}if(error)[self append:error.localizedDescription];});}];self.timer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(refresh) userInfo:nil repeats:YES];}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar{[bar resignFirstResponder];[self.search cancel];MKLocalSearchRequest *r=[MKLocalSearchRequest new];r.naturalLanguageQuery=bar.text;self.search=[[MKLocalSearch alloc]initWithRequest:r];[self.search startWithCompletionHandler:^(MKLocalSearchResponse *response,NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(error){[self append:error.localizedDescription];return;}MKMapItem *item=response.mapItems.firstObject;if(!item){[self append:@"未找到地点"];return;}[self setPoint:item.placemark.coordinate title:item.name];[self.map setRegion:MKCoordinateRegionMakeWithDistance(item.placemark.coordinate,2500,2500) animated:YES];});}];}
static double LatDelta(double x,double y){return -100+2*x+3*y+.2*y*y+.1*x*y+.2*sqrt(fabs(x))+(20*sin(6*x*M_PI)+20*sin(2*x*M_PI))*2/3+(20*sin(y*M_PI)+40*sin(y*M_PI/3))*2/3+(160*sin(y*M_PI/12)+320*sin(y*M_PI/30))*2/3;}
static double LonDelta(double x,double y){return 300+x+2*y+.1*x*x+.1*x*y+.1*sqrt(fabs(x))+(20*sin(6*x*M_PI)+20*sin(2*x*M_PI))*2/3+(20*sin(x*M_PI)+40*sin(x*M_PI/3))*2/3+(150*sin(x*M_PI/12)+300*sin(x*M_PI/30))*2/3;}
- (void)setPoint:(CLLocationCoordinate2D)c title:(NSString *)name{[self.map removeAnnotations:self.map.annotations];MKPointAnnotation *pin=[MKPointAnnotation new];pin.coordinate=c;pin.title=name;[self.map addAnnotation:pin];double lat=c.latitude,lon=c.longitude;if(lon>=72.004&&lon<=137.8347&&lat>=.8293&&lat<=55.8271){double rad=lat/180*M_PI,magic=1-.00669342162296594323*sin(rad)*sin(rad),root=sqrt(magic);lat-=LatDelta(lon-105,c.latitude-35)*180/((6378245*(1-.00669342162296594323))/(magic*root)*M_PI);lon-=LonDelta(c.longitude-105,c.latitude-35)*180/(6378245/root*cos(rad)*M_PI);}self.lat.text=[NSString stringWithFormat:@"%.8f",lat];self.lon.text=[NSString stringWithFormat:@"%.8f",lon];}
- (void)pick:(UILongPressGestureRecognizer *)g{if(g.state==UIGestureRecognizerStateBegan)[self setPoint:[self.map convertPoint:[g locationInView:self.map] toCoordinateFromView:self.map] title:@"所选位置"];}
- (void)apply{[self.view endEditing:YES];double lat=0,lon=0;NSScanner *a=[NSScanner scannerWithString:self.lat.text?:@""],*b=[NSScanner scannerWithString:self.lon.text?:@""];if(![a scanDouble:&lat]||!a.isAtEnd||![b scanDouble:&lon]||!b.isAtEnd||!isfinite(lat)||!isfinite(lon)||fabs(lat)>90||fabs(lon)>180){[self append:@"请输入有效 WGS84 经纬度"];return;}
 NSDictionary *target=@{@"latitude":@(lat),@"longitude":@(lon)};[NSUserDefaults.standardUserDefaults setObject:target forKey:@"target"];if(!self.manager)self.manager=[NETunnelProviderManager new];if(self.manager.connection.status==NEVPNStatusConnected){NSError *e=nil;NSData *message=[NSJSONSerialization dataWithJSONObject:@{@"action":@"target",@"target":target} options:0 error:nil];BOOL sent=[(NETunnelProviderSession *)self.manager.connection sendProviderMessage:message returnError:&e responseHandler:^(NSData *data){NSDictionary *result=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;dispatch_async(dispatch_get_main_queue(),^{[self append:[result[@"updated"]boolValue]?@"目标已更新，等待下一次网络定位请求。":@"更新未确认，请检查连接状态。"];});}];if(!sent)[self append:e.localizedDescription?:@"无法联系本机代理"];return;}if(self.manager.connection.status==NEVPNStatusConnecting||self.manager.connection.status==NEVPNStatusDisconnecting){[self append:@"请先恢复真实定位，等待连接停止，再应用新位置。"];return;}
 NETunnelProviderProtocol *p=[NETunnelProviderProtocol new];p.providerBundleIdentifier=@"local.wloc.standalone.tunnel";p.serverAddress=@"本机 WLOC";p.providerConfiguration=target;self.manager.protocolConfiguration=p;self.manager.localizedDescription=@"WLOC 本机定位";self.manager.enabled=YES;
 [self.manager saveToPreferencesWithCompletionHandler:^(NSError *e){if(e){dispatch_async(dispatch_get_main_queue(),^{[self append:e.localizedDescription];});return;}[self.manager loadFromPreferencesWithCompletionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{NSError *startError=error;if(!startError)[self.manager.connection startVPNTunnelAndReturnError:&startError];[self append:startError?startError.localizedDescription:@"已请求启动；连接成功仅代表代理启动，请检查重写计数与地图实际位置。"];});}];}];}
- (void)stop{[self.manager.connection stopVPNTunnel];[self append:@"已请求停止 WLOC 代理，证书规则保持不变。系统定位缓存可能需要等待刷新。"];}
- (void)refresh{NEVPNStatus s=self.manager?self.manager.connection.status:NEVPNStatusInvalid;NSArray *labels=@[@"未配置",@"未连接",@"连接中",@"已连接",@"重新连接中",@"停止中"];self.state.text=[NSString stringWithFormat:@"%@ · 网络定位模式",labels[MIN((NSUInteger)s,5)]];if(s==NEVPNStatusConnected){NSError *error=nil;[(NETunnelProviderSession *)self.manager.connection sendProviderMessage:[@"status" dataUsingEncoding:NSUTF8StringEncoding] returnError:&error responseHandler:^(NSData *data){NSDictionary *status=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;dispatch_async(dispatch_get_main_queue(),^{if(status)self.state.text=[NSString stringWithFormat:@"已连接 · 请求 %@ · 已重写 %@ · 错误 %@\n%@",status[@"requests"],status[@"patched"],status[@"failures"],status[@"last"]];});}];}}
- (void)certificate{NSURL *url=[NSBundle.mainBundle URLForResource:@"WLOC-Local" withExtension:@"mobileconfig"];UIActivityViewController *share=[[UIActivityViewController alloc]initWithActivityItems:@[url] applicationActivities:nil];share.popoverPresentationController.sourceView=self.view;[self presentViewController:share animated:YES completion:nil];[self append:@"将描述文件存入“文件”后打开安装，再到 设置 → 通用 → 关于本机 → 证书信任设置，手动信任 WLOC Local。请只在这部测试手机使用此证书。"];}
- (void)run:(NSString *)command{for(UIButton *b in self.ruleButtons)b.enabled=NO;dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{BOOL ok=NO;NSString *log=RunRules(command,&ok);dispatch_async(dispatch_get_main_queue(),^{[self append:[NSString stringWithFormat:@"%@\n%@",ok?@"检查/操作成功":@"检查/操作失败",log]];for(UIButton *b in self.ruleButtons)b.enabled=YES;});});}
- (void)check{[self run:@"check"];}
- (void)confirm:(NSString *)command title:(NSString *)title{if(self.manager.connection.status==NEVPNStatusConnected){[self append:@"请先恢复真实定位，再维护证书规则。"];return;}UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:@"仅处理 Apple 定位域名的目标规则。应用前自动备份；恢复只补回目标规则。结构、策略指纹或权限不符将拒绝操作。新版本只接受与本机已保存基准完全一致的策略。操作后需手动重启手机再验证。" preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"确认操作" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){[self run:command];}]];[self presentViewController:alert animated:YES completion:nil];}
- (void)change{
 for(UIButton *b in self.ruleButtons)b.enabled=NO;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
  BOOL ok=NO;NSString *log=RunRules(@"check",&ok);
  dispatch_async(dispatch_get_main_queue(),^{
   for(UIButton *b in self.ruleButtons)b.enabled=YES;[self append:log];
   if(!ok)return;
   if([log containsString:@"Compatibility: new-content-identical"]){
    NSRegularExpression *version=[NSRegularExpression regularExpressionWithPattern:@"Live DB content: ([0-9]+);" options:0 error:nil];
    NSRegularExpression *hash=[NSRegularExpression regularExpressionWithPattern:@"Policy SHA256: ([0-9a-f]{64})" options:0 error:nil];
    NSTextCheckingResult *v=[version firstMatchInString:log options:0 range:NSMakeRange(0,log.length)],*h=[hash firstMatchInString:log options:0 range:NSMakeRange(0,log.length)];
    if(!v||!h){[self append:@"无法确认版本和策略指纹，已拒绝操作。"];return;}
    NSString *number=[log substringWithRange:[v rangeAtIndex:1]],*digest=[log substringWithRange:[h rangeAtIndex:1]];
    [self confirm:[NSString stringWithFormat:@"apply-compatible:%@:%@",number,digest] title:[NSString stringWithFormat:@"检测到规则版本 %@，与本机 v131 基准一致，继续？",number]];
   }else if([log containsString:@"Compatibility: v131-local-baseline"]){
    [self confirm:@"apply" title:@"备份并修改定位证书规则？"];
   }else [self append:@"缺少可用基准、目标不存在或规则内容不符，未开放修改。"];});});
}
- (void)restore{[self confirm:@"restore" title:@"恢复原始证书规则？"];}
@end
@interface App : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation App
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options{self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[[UINavigationController alloc]initWithRootViewController:[Home new]];[self.window makeKeyAndVisible];return YES;}
@end
int main(int argc,char **argv){@autoreleasepool{if(argc==2)return run_rules_command(argv[1]);return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class));}}
