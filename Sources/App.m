#import <UIKit/UIKit.h>
#import <NetworkExtension/NetworkExtension.h>
#import <Security/Security.h>
#import "MapPanel.h"
#import <CoreLocation/CoreLocation.h>
#import "LocationFix.h"
#import "SearchResults.h"
#import "VPNLifecycle.h"
#import "LocalControl.h"
#import "TargetSettings.h"
#import <MapKit/MapKit.h>
#include "rules.h"
#include <sys/sysctl.h>
#include <sys/time.h>
NSString *RunRules(NSString *command,BOOL *success);
@interface Home : UIViewController <CLLocationManagerDelegate,UISearchBarDelegate,MKLocalSearchCompleterDelegate,UITableViewDataSource,UITableViewDelegate>
@property MapPanel *map;
@property UISearchBar *searchBar;
@property UILabel *searchStatus;
@property MKLocalSearchCompleter *completer;
@property MKLocalSearch *placeSearch;
@property UITableView *suggestionTable;
@property NSLayoutConstraint *suggestionHeight;
@property NSArray<NSDictionary *> *suggestions;
@property NSUInteger searchGeneration;
@property UILabel *selectionLabel,*result,*mapStatus;
@property UIButton *modifyButton,*certificateButton,*stopButton;
@property UIButton *locationButton;
@property UILabel *locationStatus;
@property CLLocationManager *locationManager;
@property BOOL waitingLocation,requestedLocation,requestedLocationPermission;
@property NSUInteger locationGeneration;
@property NETunnelProviderManager *manager;
@property NSDictionary *target,*pendingTarget;
@property NSMutableString *diagnostics;
@property NSString *phase;
@property NSUInteger operation;
@property BOOL busy,statusPending;
@property NSDate *deadline;
@property NSTimer *timer;
@property NSInteger lastVPNStatus;
@property BOOL didReloadProvider;
@property NSUInteger controlFailures;
@property NSString *lastControlError;
@property BOOL reconcilingVPN,hintPending;
@property NSUInteger confirmedOperation,hintedOperation;
@property NSDictionary *confirmedTarget;
@end
@implementation Home
- (UIButton *)button:(NSString *)title action:(SEL)selector prominent:(BOOL)prominent{
 UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];UIButtonConfiguration *c=prominent?UIButtonConfiguration.filledButtonConfiguration:UIButtonConfiguration.tintedButtonConfiguration;c.title=title;c.baseBackgroundColor=[UIColor colorWithRed:.03 green:.47 blue:.51 alpha:1];b.configuration=c;[b.heightAnchor constraintEqualToConstant:prominent?48:40].active=YES;[b addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];return b;
}
- (UILabel *)label:(CGFloat)size{UILabel *l=[UILabel new];l.numberOfLines=0;l.font=[UIFont systemFontOfSize:size];return l;}
- (void)viewDidLoad{
 [super viewDidLoad];self.view.backgroundColor=UIColor.systemBackgroundColor;self.title=@"loc x";self.phase=@"idle";self.lastVPNStatus=-1;self.diagnostics=[NSMutableString string];
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"详情" style:UIBarButtonItemStylePlain target:self action:@selector(details)];self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"坐标" style:UIBarButtonItemStylePlain target:self action:@selector(coordinates)];
 UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll];UILayoutGuide *safe=self.view.safeAreaLayoutGuide;[NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],[scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor]]];
 UIStackView *stack=[UIStackView new];stack.axis=UILayoutConstraintAxisVertical;stack.spacing=8;stack.translatesAutoresizingMaskIntoConstraints=NO;[scroll addSubview:stack];[NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-8],[stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:12],[stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-12]]];NSLayoutConstraint *fill=[stack.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor constant:-16];fill.priority=249;fill.active=YES;

 UILabel *flow=[self label:13];flow.text=@"① 选择位置    →    ② 修改    →    ③ 查看结果";flow.textAlignment=NSTextAlignmentCenter;[stack addArrangedSubview:flow];
 self.searchBar=[UISearchBar new];self.searchBar.placeholder=@"搜索城市、地址或地标";self.searchBar.searchBarStyle=UISearchBarStyleMinimal;self.searchBar.delegate=self;
 self.locationButton=[self button:@"当前位置" action:@selector(currentLocation) prominent:NO];[self.locationButton.widthAnchor constraintEqualToConstant:100].active=YES;UIStackView *searchRow=[[UIStackView alloc]initWithArrangedSubviews:@[self.searchBar,self.locationButton]];searchRow.axis=UILayoutConstraintAxisHorizontal;searchRow.alignment=UIStackViewAlignmentCenter;searchRow.spacing=4;[stack addArrangedSubview:searchRow];
 self.searchStatus=[self label:11];self.searchStatus.numberOfLines=2;self.searchStatus.hidden=YES;[stack addArrangedSubview:self.searchStatus];
 self.suggestionTable=[[UITableView alloc]initWithFrame:CGRectZero style:UITableViewStylePlain];self.suggestionTable.dataSource=self;self.suggestionTable.delegate=self;self.suggestionTable.rowHeight=54;self.suggestionTable.hidden=YES;self.suggestionHeight=[self.suggestionTable.heightAnchor constraintEqualToConstant:0];self.suggestionHeight.active=YES;[stack addArrangedSubview:self.suggestionTable];
 self.map=[MapPanel new];self.map.layer.cornerRadius=16;self.map.clipsToBounds=YES;[self.map.heightAnchor constraintGreaterThanOrEqualToConstant:160].active=YES;[stack addArrangedSubview:self.map];
 self.mapStatus=[self label:11];self.mapStatus.text=@"地图加载中；可双指缩放、拖动并点击选点。";self.mapStatus.numberOfLines=2;self.mapStatus.textColor=UIColor.secondaryLabelColor;[stack addArrangedSubview:self.mapStatus];
 self.locationStatus=[self label:11];self.locationStatus.numberOfLines=2;self.locationStatus.textColor=UIColor.secondaryLabelColor;self.locationStatus.hidden=YES;[stack addArrangedSubview:self.locationStatus];
 self.selectionLabel=[self label:14];self.selectionLabel.text=@"请在地图上点击要使用的位置";[stack addArrangedSubview:self.selectionLabel];
 self.modifyButton=[self button:@"修改" action:@selector(modify) prominent:YES];[stack addArrangedSubview:self.modifyButton];
 self.result=[self label:13];self.result.text=@"点击修改将自动检查证书和代理；必要时先备份并处理单条定位规则。";[stack addArrangedSubview:self.result];
 self.certificateButton=[self button:@"安装证书（首次需要系统确认）" action:@selector(certificate) prominent:NO];self.certificateButton.hidden=YES;[stack addArrangedSubview:self.certificateButton];
 self.stopButton=[self button:@"恢复真实定位" action:@selector(stop) prominent:NO];[stack addArrangedSubview:self.stopButton];
 __weak Home *weakSelf=self;self.map.selection=^(double lat,double lon){[weakSelf selectLatitude:lat longitude:lon];};self.map.notice=^(NSString *message){weakSelf.mapStatus.text=message;};
 self.map.diagnostic=^(NSString *message){[weakSelf append:[@"地图请求：" stringByAppendingString:message]];};
 NSDictionary *saved=[NSUserDefaults.standardUserDefaults dictionaryForKey:@"target"];if([self validTarget:saved]){self.target=saved;self.selectionLabel.text=[NSString stringWithFormat:@"上次目标 %.6f, %.6f · WGS84",[saved[@"latitude"]doubleValue],[saved[@"longitude"]doubleValue]];[self.map showLatitude:[saved[@"latitude"]doubleValue] longitude:[saved[@"longitude"]doubleValue] selected:YES];}
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(vpnStatusChanged:) name:NEVPNStatusDidChangeNotification object:nil];
 [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive) name:UIApplicationDidBecomeActiveNotification object:nil];self.timer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
}
- (void)append:(NSString *)text{if(!text.length)return;[self.diagnostics appendFormat:@"%@\n",text];if(self.diagnostics.length>24000)[self.diagnostics deleteCharactersInRange:NSMakeRange(0,self.diagnostics.length-24000)];}
- (BOOL)validTarget:(NSDictionary *)t{if(![t isKindOfClass:NSDictionary.class]||![t[@"latitude"]isKindOfClass:NSNumber.class]||![t[@"longitude"]isKindOfClass:NSNumber.class])return NO;double a=[t[@"latitude"]doubleValue],b=[t[@"longitude"]doubleValue];return isfinite(a)&&isfinite(b)&&fabs(a)<=90&&fabs(b)<=180;}
- (void)selectLatitude:(double)lat longitude:(double)lon{if(self.busy)return;[self cancelSearch];[self.searchBar resignFirstResponder];self.searchBar.showsCancelButton=NO;if(self.waitingLocation){[self cancelLocation];self.locationStatus.text=@"已取消读取当前位置。";}NSDictionary *t=@{@"latitude":@(lat),@"longitude":@(lon)};if(![self validTarget:t])return;self.operation++;self.hintPending=NO;self.statusPending=NO;self.pendingTarget=nil;self.certificateButton.hidden=YES;self.phase=@"idle";self.target=t;self.selectionLabel.text=[NSString stringWithFormat:@"已选 %.6f, %.6f · WGS84",lat,lon];self.result.text=@"位置已选择，点击修改即可自动检查并启用。";}
- (void)cancelSearch{self.searchGeneration++;self.completer.delegate=nil;[self.completer cancel];self.completer=nil;[self.placeSearch cancel];self.placeSearch=nil;self.suggestions=@[];self.suggestionTable.hidden=YES;self.suggestionHeight.constant=0;[self.suggestionTable reloadData];self.searchStatus.hidden=YES;}
- (void)searchBarTextDidBeginEditing:(UISearchBar *)bar{bar.showsCancelButton=YES;}
- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text{
 [self cancelSearch];NSString *query=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!query.length||self.busy)return;NSUInteger generation=self.searchGeneration;self.searchStatus.hidden=NO;self.searchStatus.text=@"正在查找地点建议…";
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{if(generation!=self.searchGeneration||self.busy)return;self.completer=[MKLocalSearchCompleter new];self.completer.delegate=self;self.completer.resultTypes=MKLocalSearchCompleterResultTypeAddress|MKLocalSearchCompleterResultTypePointOfInterest;self.completer.queryFragment=query;});
}
- (void)showSuggestions:(NSArray<NSDictionary *> *)items{self.suggestions=items;self.suggestionTable.hidden=!items.count;self.suggestionHeight.constant=MIN(items.count*54,216);[self.suggestionTable reloadData];self.searchStatus.hidden=NO;self.searchStatus.text=items.count?@"点击下方候选地点选择位置":@"未找到候选地点，请补充城市或地标名称。";}
- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer{if(completer!=self.completer||self.busy)return;NSMutableArray *items=[NSMutableArray array];for(MKLocalSearchCompletion *c in completer.results){[items addObject:@{@"title":c.title?:@"地点",@"subtitle":c.subtitle?:@"",@"completion":c}];if(items.count==12)break;}[self showSuggestions:items];}
- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error{if(completer!=self.completer)return;[self showSuggestions:@[]];self.searchStatus.text=[NSString stringWithFormat:@"地点建议加载失败（%@ %ld）。可点键盘搜索重试。",error.domain,(long)error.code];}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return self.suggestions.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path{UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"suggestion"];if(!cell)cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"suggestion"];NSDictionary *item=self.suggestions[path.row];cell.textLabel.text=item[@"title"];cell.detailTextLabel.text=item[@"subtitle"];return cell;}
- (void)selectSearchItem:(MKMapItem *)item{CLLocationCoordinate2D c=item.placemark.coordinate;if(!CLLocationCoordinate2DIsValid(c)){self.searchStatus.text=@"该地点未返回有效坐标，请选择其他结果。";return;}NSString *name=item.name?:@"所选地点";[self selectLatitude:c.latitude longitude:c.longitude];[self.map showLatitude:c.latitude longitude:c.longitude selected:YES];self.selectionLabel.text=[NSString stringWithFormat:@"%@ · %.6f, %.6f",name,c.latitude,c.longitude];}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path{
 if(self.busy||path.row>=self.suggestions.count)return;NSDictionary *item=self.suggestions[path.row];if(item[@"item"]){[self selectSearchItem:item[@"item"]];return;}MKLocalSearchCompletion *completion=item[@"completion"];[self cancelSearch];[self.searchBar resignFirstResponder];self.searchBar.showsCancelButton=NO;self.searchStatus.hidden=NO;self.searchStatus.text=@"正在读取所选地点坐标…";[self runPlaceSearch:[[MKLocalSearchRequest alloc]initWithCompletion:completion] direct:YES];
}
- (void)runPlaceSearch:(MKLocalSearchRequest *)request direct:(BOOL)direct{NSUInteger generation=self.searchGeneration;self.placeSearch=[[MKLocalSearch alloc]initWithRequest:request];[self.placeSearch startWithCompletionHandler:^(MKLocalSearchResponse *response,NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(generation!=self.searchGeneration||self.busy)return;self.placeSearch=nil;if(error||!response.mapItems.count){self.searchStatus.hidden=NO;self.searchStatus.text=error?[NSString stringWithFormat:@"搜索失败（%@ %ld），请检查网络或更换关键词。",error.domain,(long)error.code]:@"没有找到地点，请补充城市名称。";return;}if(direct){[self selectSearchItem:response.mapItems.firstObject];return;}NSMutableArray *items=[NSMutableArray array];for(MKMapItem *item in response.mapItems){[items addObject:@{@"title":item.name?:@"地点",@"subtitle":item.placemark.title?:@"",@"item":item}];if(items.count==12)break;}[self showSuggestions:items];});}];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(generation==self.searchGeneration&&self.placeSearch){[self cancelSearch];self.searchStatus.hidden=NO;self.searchStatus.text=@"搜索超时，请检查网络后重试。";}});}
- (void)searchBarCancelButtonClicked:(UISearchBar *)bar{[self cancelSearch];[bar resignFirstResponder];bar.showsCancelButton=NO;}
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar{if(self.busy)return;NSString *query=[bar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];[self cancelSearch];[bar resignFirstResponder];bar.showsCancelButton=NO;if(!query.length)return;self.searchStatus.hidden=NO;self.searchStatus.text=@"正在搜索地点…";MKLocalSearchRequest *request=[MKLocalSearchRequest new];request.naturalLanguageQuery=query;[self runPlaceSearch:request direct:NO];}
- (void)cancelLocation{self.locationGeneration++;self.waitingLocation=NO;self.requestedLocation=NO;self.requestedLocationPermission=NO;self.locationManager.delegate=nil;[self.locationManager stopUpdatingLocation];self.locationManager=nil;self.locationButton.enabled=!self.busy;}
- (void)locationFailure:(NSString *)message{[self cancelLocation];self.locationStatus.hidden=NO;self.locationStatus.text=message;}
- (void)currentLocation{
 if(self.busy||self.waitingLocation)return;[self cancelSearch];[self.searchBar resignFirstResponder];self.searchBar.showsCancelButton=NO;[self cancelLocation];self.waitingLocation=YES;self.locationButton.enabled=NO;self.locationStatus.hidden=NO;self.locationStatus.text=@"正在读取系统当前位置…";self.locationManager=[CLLocationManager new];self.locationManager.desiredAccuracy=kCLLocationAccuracyBest;self.locationManager.delegate=self;[self continueLocationRequest];
}
- (void)continueLocationRequest{
 if(!self.waitingLocation)return;CLAuthorizationStatus status=self.locationManager.authorizationStatus;
 if(status==kCLAuthorizationStatusDenied||status==kCLAuthorizationStatusRestricted){[self locationFailure:@"无法读取当前位置。请在系统设置开启定位服务，并允许 loc x 使用期间访问位置。"];return;}
 if(status==kCLAuthorizationStatusNotDetermined){self.locationStatus.text=@"请在系统弹窗允许使用期间访问位置。";if(!self.requestedLocationPermission){self.requestedLocationPermission=YES;[self.locationManager requestWhenInUseAuthorization];}return;}
 if(self.requestedLocation)return;self.requestedLocation=YES;self.locationStatus.text=@"正在获取当前位置…";[self.locationManager requestLocation];NSUInteger generation=self.locationGeneration;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.waitingLocation&&generation==self.locationGeneration)[self locationFailure:@"获取当前位置超时，请移到信号较好的地方后重试。"];});
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager{if(manager==self.locationManager&&self.waitingLocation)[self continueLocationRequest];}
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations{
 if(manager!=self.locationManager||!self.waitingLocation)return;CLLocation *fix=nil;NSDate *now=NSDate.date;for(CLLocation *candidate in locations.reverseObjectEnumerator)if(WLOCUsableLocation(candidate,now)){fix=candidate;break;}
 if(!fix){[self locationFailure:@"暂未取得有效的新位置，请重试。"];return;}[self cancelLocation];[self.map showCurrentLatitude:fix.coordinate.latitude longitude:fix.coordinate.longitude accuracy:fix.horizontalAccuracy];self.locationStatus.text=[NSString stringWithFormat:@"蓝点：系统当前位置，精度约 %.0f 米。代理开启时可能是修改后的位置。",fix.horizontalAccuracy];
}
- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error{if(manager!=self.locationManager||!self.waitingLocation)return;[self locationFailure:error.code==kCLErrorDenied?@"定位权限不可用，请在系统设置允许 loc x 使用期间访问位置。":[NSString stringWithFormat:@"获取当前位置失败（%@ %ld），请重试。",error.domain,(long)error.code]];}
- (void)progress:(NSString *)phase message:(NSString *)message{[self cancelSearch];self.searchBar.userInteractionEnabled=NO;if(self.waitingLocation){[self cancelLocation];self.locationStatus.text=@"已取消读取当前位置。";}self.phase=phase;self.result.text=message;self.busy=YES;self.stopButton.enabled=![phase isEqual:@"rules"];self.modifyButton.enabled=NO;self.map.userInteractionEnabled=NO;self.locationButton.enabled=NO;self.navigationItem.leftBarButtonItem.enabled=NO;[self append:message];}
- (void)unlock{self.searchBar.userInteractionEnabled=YES;self.stopButton.enabled=YES;self.busy=NO;self.modifyButton.enabled=YES;self.map.userInteractionEnabled=YES;self.locationButton.enabled=!self.waitingLocation;self.navigationItem.leftBarButtonItem.enabled=YES;}
- (void)fail:(NSString *)message operation:(NSUInteger)op{if(op!=self.operation)return;self.phase=@"failed";self.result.text=[@"未完成：" stringByAppendingString:message];self.pendingTarget=nil;[self append:self.result.text];[self unlock];}
- (NSError *)certificateError{
 NSData *der=[NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"server" withExtension:@"der"]];SecCertificateRef leaf=der?SecCertificateCreateWithData(NULL,(__bridge CFDataRef)der):NULL;SecPolicyRef policy=SecPolicyCreateSSL(true,CFSTR("gs-loc.apple.com"));SecTrustRef trust=NULL;CFErrorRef error=NULL;BOOL trusted=NO;
 if(leaf&&SecTrustCreateWithCertificates(leaf,policy,&trust)==errSecSuccess){SecTrustSetNetworkFetchAllowed(trust,false);trusted=SecTrustEvaluateWithError(trust,&error);}NSError *result=trusted?nil:(error?CFBridgingRelease(error):[NSError errorWithDomain:@"WLOC 证书资源" code:1 userInfo:@{NSLocalizedDescriptionKey:@"缺少本机证书"}]);if(trust)CFRelease(trust);if(leaf)CFRelease(leaf);CFRelease(policy);return result;
}
- (void)executeRules:(NSString *)command completion:(void (^)(BOOL,NSString *))completion{dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{BOOL ok=NO;NSString *log=RunRules(command,&ok);dispatch_async(dispatch_get_main_queue(),^{[self append:log];completion(ok,log);});});}
- (NSString *)bootSession{struct timeval boot={0};size_t size=sizeof(boot);if(sysctlbyname("kern.boottime",&boot,&size,NULL,0)!=0)return @"unavailable";return [NSString stringWithFormat:@"%lld.%d",(long long)boot.tv_sec,(int)boot.tv_usec];}
- (BOOL)restartRequired{NSString *saved=[NSUserDefaults.standardUserDefaults stringForKey:@"rulesRestartBoot"];return saved&&([saved isEqual:[self bootSession]]||[[self bootSession]isEqual:@"unavailable"]);}
- (void)recordRestartRequired{[NSUserDefaults.standardUserDefaults setObject:[self bootSession] forKey:@"rulesRestartBoot"];}
- (void)modify{
 if(self.busy)return;if(self.waitingLocation){[self cancelLocation];self.locationStatus.text=@"已取消读取当前位置。";}self.statusPending=NO;[self.view endEditing:YES];if(![self validTarget:self.target]){self.result.text=@"请先在地图上点击选择位置。";return;}
 self.didReloadProvider=NO;self.controlFailures=0;self.lastControlError=nil;NSUInteger op=++self.operation;self.pendingTarget=[self.target copy];self.certificateButton.hidden=YES;[self progress:@"checking" message:@"正在自动检查：本机证书…"];
 if([self restartRequired]){[self fail:@"上次规则操作后尚未重启，请重启 iPhone 后再点击修改。" operation:op];return;}
 NSError *certificateError=[self certificateError];if(certificateError){self.phase=@"certificate";self.result.text=@"首次需要安装并完全信任本机证书。点击下方安装；完成系统设置后返回，将自动继续。";[self append:certificateError.localizedDescription];self.certificateButton.hidden=NO;[self unlock];return;}
 [self loadManagerForOperation:op];
}
- (void)becameActive{[self showActivationHint];if(self.manager&&![self.phase isEqual:@"manual"]&&![self.phase isEqual:@"certificate"]){NSUInteger op=self.operation;self.reconcilingVPN=YES;[NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error){dispatch_async(dispatch_get_main_queue(),^{self.reconcilingVPN=NO;if(op!=self.operation)return;if(error)[self append:[NSString stringWithFormat:@"返回前台配置刷新：%@ %ld %@",error.domain,(long)error.code,error.localizedDescription]];for(NETunnelProviderManager *m in managers)if([((NETunnelProviderProtocol *)m.protocolConfiguration).providerBundleIdentifier isEqual:@"local.wloc.standalone.tunnel"]){self.manager=m;break;}if(WLOCShouldRecheckOnForeground(self.manager.connection.status,[self validTarget:self.pendingTarget],self.confirmedOperation==op&&self.confirmedTarget!=nil)){[self append:@"从系统设置返回，连接仍在；重新核对实际代理，旧状态错误仅保留在日志。"];self.pendingTarget=self.pendingTarget?:self.confirmedTarget;self.phase=@"connecting";self.deadline=[NSDate dateWithTimeIntervalSinceNow:15];self.result.text=@"VPN 已连接，正在后台核对坐标…";}[self refresh];});}];return;}if([self.phase isEqual:@"manual"]){NSUInteger op=self.operation;[NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(op!=self.operation||![self.phase isEqual:@"manual"])return;for(NETunnelProviderManager *m in managers)if([((NETunnelProviderProtocol *)m.protocolConfiguration).providerBundleIdentifier isEqual:@"local.wloc.standalone.tunnel"]){self.manager=m;break;}if(error)[self append:error.localizedDescription];[self refresh];});}];return;}if([self.phase isEqual:@"certificate"]&&self.pendingTarget&&![self certificateError]){self.certificateButton.hidden=YES;[self progress:@"checking" message:@"证书信任已通过，自动继续…"];[self loadManagerForOperation:self.operation];}}
- (void)loadManagerForOperation:(NSUInteger)op{
 [self progress:@"checking" message:@"证书信任通过，正在检查代理配置…"];
 [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(op!=self.operation)return;if(error){[self fail:error.localizedDescription operation:op];return;}self.manager=nil;for(NETunnelProviderManager *m in managers)if([((NETunnelProviderProtocol *)m.protocolConfiguration).providerBundleIdentifier isEqual:@"local.wloc.standalone.tunnel"]){self.manager=m;break;}if(!self.manager)self.manager=[NETunnelProviderManager new];NEVPNStatus s=self.manager.connection.status;WLOCConnectionAction action=WLOCActionForStatus(s);if(action==WLOCUseConnected){[self append:@"复用已连接的 WLOC 代理，直接同步坐标，不请求断开。"];[self adoptManualConnection:op];}else if(action==WLOCWaitConnecting){[self progress:@"waiting" message:@"已有代理正在连接，等待其完成后同步坐标…"];self.deadline=[NSDate dateWithTimeIntervalSinceNow:60];}else if(action==WLOCWaitDisconnecting){[self progress:@"stopping" message:@"正在等待旧连接完成断开…"];self.deadline=[NSDate dateWithTimeIntervalSinceNow:12];}else [self checkRulesForOperation:op];});}];
}
- (void)checkRulesForOperation:(NSUInteger)op{
 [self progress:@"checking" message:@"正在自动检查定位规则…"];
 [self executeRules:@"check" completion:^(BOOL ok,NSString *log){if(op!=self.operation)return;if(!ok){[self fail:@"无法完成规则检查，请在详情查看错误。" operation:op];return;}if([log containsString:@"Target rule: absent"]){[self append:@"目标规则不存在，无需修改，不创建恢复基线。"];[self startProxyForOperation:op];return;}
 NSString *command=nil;if([log containsString:@"Compatibility: v131-local-baseline"])command=@"apply";else if([log containsString:@"Compatibility: new-content-identical"]){NSRegularExpression *version=[NSRegularExpression regularExpressionWithPattern:@"Live DB content: ([0-9]+);" options:0 error:nil],*hash=[NSRegularExpression regularExpressionWithPattern:@"Policy SHA256: ([0-9a-f]{64})" options:0 error:nil];NSTextCheckingResult *v=[version firstMatchInString:log options:0 range:NSMakeRange(0,log.length)],*h=[hash firstMatchInString:log options:0 range:NSMakeRange(0,log.length)];if(v&&h)command=[NSString stringWithFormat:@"apply-compatible:%@:%@",[log substringWithRange:[v rangeAtIndex:1]],[log substringWithRange:[h rangeAtIndex:1]]];}
 if(!command){[self fail:@"目标规则无法安全识别，已停止。详情中有检查结果。" operation:op];return;}
 [self progress:@"rules" message:@"正在备份并处理已识别的单条定位规则…"];[self executeRules:command completion:^(BOOL applied,NSString *output){if(op!=self.operation)return;if(!applied){[self fail:@"规则修改失败，未启动定位代理。请查看详情。" operation:op];return;}[self recordRestartRequired];[self fail:@"规则已备份并修改。需要手动重启 iPhone，之后回到这里点击修改。" operation:op];}];}];
}
- (BOOL)hasExistingConfiguration{NETunnelProviderProtocol *p=(id)self.manager.protocolConfiguration;return [p isKindOfClass:NETunnelProviderProtocol.class]&&[p.providerBundleIdentifier isEqual:@"local.wloc.standalone.tunnel"];}
- (void)manualConnectionRequired:(NSError *)error operation:(NSUInteger)op{if(op!=self.operation)return;[self append:[NSString stringWithFormat:@"自动连接错误：%@ %ld %@",error.domain?:@"未启用",(long)error.code,error.localizedDescription?:@"系统未允许自动连接"]];self.phase=@"manual";if(self.manager.connection.status==NEVPNStatusConnected){[self append:@"自动连接报告错误，但系统已连接；仅记录日志，继续核对实际代理。"];[self adoptManualConnection:op];return;}self.result.text=@"请到 设置 → VPN 连接本机定位配置，再返回；App 会自动同步并核对本次坐标。";[self unlock];}
- (void)beginTunnelForOperation:(NSUInteger)op{
 if(op!=self.operation)return;NSString *token=[self controlToken];if(!token){[self fail:@"无法生成本机通信密钥，请重试。" operation:op];return;}NSError *error=nil;BOOL started=[(NETunnelProviderSession *)self.manager.connection startTunnelWithOptions:@{@"target":self.pendingTarget,@"controlToken":token,@"sequence":[self nextControlSequence]} andReturnError:&error];
 if(!started||error){[self manualConnectionRequired:error operation:op];return;}
 self.deadline=[NSDate dateWithTimeIntervalSinceNow:60];[self progress:@"connecting" message:@"正在连接已有本机代理并核对所选坐标…"];[self refresh];
}
- (void)startProxyForOperation:(NSUInteger)op{
 if(op!=self.operation)return;if([self certificateError]){[self fail:@"系统证书信任状态已改变，请重试。" operation:op];return;}
 if([self hasExistingConfiguration]){[self append:@"检测到已有 WLOC 配置，直接复用，不重复保存或添加。"];if(!self.manager.enabled){[self manualConnectionRequired:nil operation:op];return;}[self beginTunnelForOperation:op];return;}
 [self progress:@"starting" message:@"首次创建 WLOC 配置，请允许系统 VPN 授权…"];
 NETunnelProviderProtocol *p=[NETunnelProviderProtocol new];p.providerBundleIdentifier=@"local.wloc.standalone.tunnel";p.serverAddress=@"本机 WLOC";p.providerConfiguration=self.pendingTarget;self.manager.protocolConfiguration=p;self.manager.localizedDescription=@"WLOC 本机定位";self.manager.enabled=YES;
 [self.manager saveToPreferencesWithCompletionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(op!=self.operation)return;if(error){[self fail:error.localizedDescription operation:op];return;}[self.manager loadFromPreferencesWithCompletionHandler:^(NSError *e){dispatch_async(dispatch_get_main_queue(),^{if(op!=self.operation)return;if(e){[self fail:e.localizedDescription operation:op];return;}[self beginTunnelForOperation:op];});}];});}];
}
- (NSNumber *)nextControlSequence{unsigned long long old=[[NSUserDefaults.standardUserDefaults objectForKey:@"hostControlSequence"]unsignedLongLongValue];unsigned long long value=MAX(old+1,(unsigned long long)(NSDate.date.timeIntervalSince1970*1000000));[NSUserDefaults.standardUserDefaults setObject:@(value) forKey:@"hostControlSequence"];return @(value);}
- (NSString *)controlToken{NSString *token=WLOCValidatedControlToken([NSUserDefaults.standardUserDefaults stringForKey:@"controlToken"]);if(token)return token;uint8_t bytes[32];if(SecRandomCopyBytes(kSecRandomDefault,sizeof(bytes),bytes)!=errSecSuccess)return nil;NSMutableString *value=[NSMutableString string];for(int i=0;i<32;i++)[value appendFormat:@"%02x",bytes[i]];[NSUserDefaults.standardUserDefaults setObject:value forKey:@"controlToken"];return value;}
- (void)control:(NSDictionary *)message operation:(NSUInteger)op completion:(void (^)(NSDictionary *,NSError *))completion{NSString *token=[self controlToken];dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{NSError *error=nil;NSDictionary *response=WLOCControlRequest(token,message,&error);dispatch_async(dispatch_get_main_queue(),^{if(op!=self.operation)return;completion(response,error);});});}
- (void)reloadProviderForOperation:(NSUInteger)op{if(op!=self.operation||self.didReloadProvider)return;self.didReloadProvider=YES;self.statusPending=NO;self.controlFailures=0;[self stopTunnel:@"旧扩展未提供新版本机通信，重载一次以更新"];[self progress:@"stopping" message:@"正在重载旧版扩展以恢复坐标通信（本次仅一次）…"];self.deadline=[NSDate dateWithTimeIntervalSinceNow:12];}
- (void)adoptManualConnection:(NSUInteger)op{
 if(op!=self.operation)return;if([self certificateError]){[self fail:@"证书信任未通过，请完成系统设置后重试。" operation:op];return;}
 [self progress:@"checking" message:@"正在复查规则并直接同步本机代理坐标…"];
 [self executeRules:@"check" completion:^(BOOL ok,NSString *log){if(op!=self.operation)return;if(!ok||![log containsString:@"Target rule: absent"]){[self stopTunnel:@"连接后的规则复查未通过"];[self fail:@"连接后的规则复查未通过，请重试。" operation:op];return;}[self progress:@"updating" message:@"正在直接下发坐标并读取代理确认…"];
 [self control:@{@"action":@"target",@"target":self.pendingTarget,@"sequence":[self nextControlSequence]} operation:op completion:^(NSDictionary *reply,NSError *error){if(error||![reply[@"updated"]boolValue]){self.lastControlError=WLOCControlErrorMessage(error);[self append:[@"本机坐标通道失败：" stringByAppendingString:self.lastControlError]];if(!self.didReloadProvider){[self reloadProviderForOperation:op];return;}[self fail:[@"本机代理没有确认坐标：" stringByAppendingString:self.lastControlError] operation:op];return;}self.deadline=[NSDate dateWithTimeIntervalSinceNow:60];[self progress:@"connecting" message:@"代理已回复，正在核对网络就绪状态和坐标…"];[self receiveStatus:reply operation:op];}];}];
}
- (BOOL)connectionIsReady{return self.manager.connection.status==NEVPNStatusConnected;}
- (void)receiveStatus:(NSDictionary *)status operation:(NSUInteger)op{
 if(op!=self.operation||(![self.phase isEqual:@"connecting"]&&![self.phase isEqual:@"success"]&&![self.phase isEqual:@"requestError"]))return;
 if(![self connectionIsReady]){self.result.text=@"本机代理已回复，等待系统连接确认…";return;}
 if([status[@"controlAPI"]integerValue]!=1||![status[@"ready"]boolValue]){self.lastControlError=@"本机代理的网络配置尚未就绪";self.result.text=@"本机代理已响应，但网络配置尚未就绪；继续等待…";return;}
 NSDictionary *target=status[@"target"];BOOL matching=[self validTarget:target]&&self.pendingTarget&&fabs([target[@"latitude"]doubleValue]-[self.pendingTarget[@"latitude"]doubleValue])<1e-7&&fabs([target[@"longitude"]doubleValue]-[self.pendingTarget[@"longitude"]doubleValue])<1e-7;if(!matching){[self stopTunnel:@"代理回传坐标与本次目标不符"];[self fail:@"代理未确认本次目标坐标，已停止。" operation:op];return;}
 if([status[@"failures"]unsignedIntegerValue]>0&&[status[@"patched"]unsignedIntegerValue]==0){self.phase=@"requestError";[self unlock];self.result.text=[NSString stringWithFormat:@"VPN 保持连接，但定位响应尚未重写：%@",status[@"last"]?:@"请求失败"];[self append:self.result.text];return;}
 self.phase=@"success";self.confirmedOperation=op;self.confirmedTarget=[self.pendingTarget copy];[self unlock];[NSUserDefaults.standardUserDefaults setObject:self.pendingTarget forKey:@"target"];
 if([status[@"patched"]unsignedIntegerValue]>0)self.result.text=[NSString stringWithFormat:@"成功：已重写 %@ 条网络定位响应。\n请在系统中手动关闭并重新打开定位服务。",status[@"patched"]];else self.result.text=@"成功：代理已启用并确认坐标，实际位置待验证。\n请在系统中手动关闭并重新打开定位服务，再查看位置。";if(self.hintedOperation!=op){self.hintedOperation=op;self.hintPending=YES;}[self showActivationHint];
}
- (void)refresh{
 if(self.reconcilingVPN)return;
 NEVPNStatus s=self.manager?self.manager.connection.status:NEVPNStatusInvalid;[self recordVPNStatus:s];
 if([self.phase isEqual:@"waiting"]){if(s==NEVPNStatusConnected)[self adoptManualConnection:self.operation];else if(s==NEVPNStatusDisconnected||s==NEVPNStatusInvalid)[self fail:@"系统未能建立已有连接，请查看运行信息并重试。" operation:self.operation];else if(self.deadline.timeIntervalSinceNow<0){[self stopTunnel:@"已有启动长时间未完成"];[self fail:@"已有 VPN 启动超时，请重试。" operation:self.operation];}return;}
 if([self.phase isEqual:@"manual"]){if(s==NEVPNStatusConnected)[self adoptManualConnection:self.operation];return;}
 if([self.phase isEqual:@"stopping"]){if(s==NEVPNStatusDisconnected||s==NEVPNStatusInvalid)[self checkRulesForOperation:self.operation];else if(self.deadline.timeIntervalSinceNow<0)[self fail:@"旧代理未停止，请重试。" operation:self.operation];return;}
 BOOL connecting=[self.phase isEqual:@"connecting"],success=[self.phase isEqual:@"success"]||[self.phase isEqual:@"requestError"];if(!connecting&&!success)return;
 if(connecting&&self.deadline.timeIntervalSinceNow<0){if(WLOCShouldCancelAfterTimeout(s)){[self stopTunnel:@"启动等待超时，取消尚未建立的连接"];[self fail:@"代理启动超时，系统未报告已连接；请查看 VPN 状态日志。" operation:self.operation];}else{[self append:@"VPN 已连接，坐标状态确认超时；保留连接。"];[self fail:[NSString stringWithFormat:@"VPN 显示连接，但%@。本次位置未确认，连接已保留。",self.lastControlError?:@"本机代理未确认就绪及坐标"] operation:self.operation];}return;}
 if(success&&(s==NEVPNStatusDisconnected||s==NEVPNStatusInvalid)){[self fail:@"定位代理已断开，可点击修改重新启用。" operation:self.operation];return;}
 if(s!=NEVPNStatusConnected||self.statusPending)return;self.statusPending=YES;NSUInteger op=self.operation;
 [self control:@{@"action":@"status"} operation:op completion:^(NSDictionary *v,NSError *error){self.statusPending=NO;if(error){self.controlFailures++;self.lastControlError=WLOCControlErrorMessage(error);[self append:[@"本机代理状态读取失败：" stringByAppendingString:self.lastControlError]];if(self.controlFailures>=2&&!self.didReloadProvider&&[self.phase isEqual:@"connecting"])[self reloadProviderForOperation:op];return;}self.controlFailures=0;self.lastControlError=nil;[self receiveStatus:v operation:op];}];
}
- (void)showActivationHint{if(!self.hintPending||![self.phase isEqual:@"success"]||![self connectionIsReady]||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive||!self.view.window||self.presentedViewController||self.navigationController.topViewController!=self)return;self.hintPending=NO;UIAlertController *a=[UIAlertController alertControllerWithTitle:@"修改已启用" message:@"请到 设置 → 隐私 → 定位服务，手动关闭后再重新打开定位服务，然后回到目标应用查看位置。" preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)recordVPNStatus:(NEVPNStatus)status{if(self.lastVPNStatus==status)return;self.lastVPNStatus=status;NSArray *names=@[@"未配置",@"已断开",@"连接中",@"已连接",@"重新连接中",@"断开中"];[self append:[NSString stringWithFormat:@"%@ VPN 状态：%@ (%ld)，流程 %@",NSDate.date,names[MIN((NSUInteger)status,5)],(long)status,self.phase]];}
- (void)vpnStatusChanged:(NSNotification *)note{if(note.object==self.manager.connection){[self recordVPNStatus:self.manager.connection.status];[self refresh];}}
- (void)stopTunnel:(NSString *)reason{[self append:[@"App 主动请求断开 VPN：" stringByAppendingString:reason]];[self.manager.connection stopVPNTunnel];}
- (void)stop{if([self.phase isEqual:@"rules"]){self.result.text=@"规则事务进行中，请等待结束。";return;}self.operation++;self.hintPending=NO;self.statusPending=NO;self.pendingTarget=nil;self.certificateButton.hidden=YES;[self stopTunnel:@"用户点击恢复真实定位"];NSUInteger op=self.operation;[NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray *managers,NSError *error){dispatch_async(dispatch_get_main_queue(),^{if(op!=self.operation)return;for(NETunnelProviderManager *m in managers)if([((NETunnelProviderProtocol *)m.protocolConfiguration).providerBundleIdentifier isEqual:@"local.wloc.standalone.tunnel"]){self.manager=m;[self append:@"App 主动请求断开 VPN：用户点击恢复真实定位"];[m.connection stopVPNTunnel];}if(error){self.result.text=error.localizedDescription;[self append:error.localizedDescription];}});}];self.phase=@"idle";self.result.text=@"已请求停止代理，系统网络定位将恢复；定位缓存可能需要等待刷新。";[self unlock];}
- (void)certificate{NSURL *url=[NSBundle.mainBundle URLForResource:@"WLOC-Local" withExtension:@"mobileconfig"];if(!url){self.result.text=@"安装包缺少证书描述文件，请重新安装。";return;}UIActivityViewController *share=[[UIActivityViewController alloc]initWithActivityItems:@[url] applicationActivities:nil];share.popoverPresentationController.sourceView=self.certificateButton;[self presentViewController:share animated:YES completion:nil];self.result.text=@"将证书存入“文件”并打开安装；到 设置 → 通用 → 关于本机 → 证书信任设置 启用本机 WLOC 完全信任。返回后自动继续。";}
- (void)coordinates{
 if(self.busy)return;UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"跳转到坐标" message:@"WGS84 经纬度。确认后会在地图上标记该位置。" preferredStyle:UIAlertControllerStyleAlert];[alert addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"纬度 -90～90";f.keyboardType=UIKeyboardTypeNumbersAndPunctuation;f.text=self.target?[self.target[@"latitude"]description]:@"";}];[alert addTextFieldWithConfigurationHandler:^(UITextField *f){f.placeholder=@"经度 -180～180";f.keyboardType=UIKeyboardTypeNumbersAndPunctuation;f.text=self.target?[self.target[@"longitude"]description]:@"";}];[alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];[alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){double lat=0,lon=0;NSScanner *x=[NSScanner scannerWithString:alert.textFields[0].text?:@""],*y=[NSScanner scannerWithString:alert.textFields[1].text?:@""];if(![x scanDouble:&lat]||!x.isAtEnd||![y scanDouble:&lon]||!y.isAtEnd||![self validTarget:@{@"latitude":@(lat),@"longitude":@(lon)}]){self.result.text=@"坐标无效，请重新输入。";return;}[self selectLatitude:lat longitude:lon];[self.map showLatitude:lat longitude:lon selected:YES];}]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)details{
 UIAlertController *a=[UIAlertController alertControllerWithTitle:@"详情与维护" message:@"修改会自动检查证书与规则；必要时备份并仅修改定位目标规则。停止代理不会恢复证书规则。" preferredStyle:UIAlertControllerStyleActionSheet];[a addAction:[UIAlertAction actionWithTitle:@"查看运行信息" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){UIViewController *v=[UIViewController new];v.title=@"运行信息";UITextView *text=[UITextView new];text.editable=NO;text.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];text.text=self.diagnostics.length?self.diagnostics:@"尚无操作日志。";v.view=text;[self.navigationController pushViewController:v animated:YES];}]];[a addAction:[UIAlertAction actionWithTitle:@"重新加载地图" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self.map retry];}]];[a addAction:[UIAlertAction actionWithTitle:@"恢复原始证书规则" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[self restoreRules];}]];[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];
}
- (void)restoreRules{if(self.busy){self.result.text=@"操作进行中，请稍后。";return;}NEVPNStatus s=self.manager.connection.status;if(s==NEVPNStatusConnected||s==NEVPNStatusConnecting||s==NEVPNStatusDisconnecting||s==NEVPNStatusReasserting){self.result.text=@"请先恢复真实定位，待代理断开后再恢复规则。";return;}NSUInteger op=++self.operation;[self progress:@"rules" message:@"正在从本机备份恢复目标规则…"];[self executeRules:@"restore" completion:^(BOOL ok,NSString *log){if(op!=self.operation)return;self.pendingTarget=nil;if(ok)[self recordRestartRequired];self.phase=ok?@"idle":@"failed";self.result.text=ok?@"规则已恢复，请重启 iPhone 后验证。":@"规则恢复失败，请查看详情；不会使用其他设备的备份。";[self unlock];}];}
@end
@interface App : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation App
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options{self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=[[UINavigationController alloc]initWithRootViewController:[Home new]];[self.window makeKeyAndVisible];return YES;}
@end
int main(int argc,char **argv){@autoreleasepool{if(argc==2)return run_rules_command(argv[1]);return UIApplicationMain(argc,argv,nil,NSStringFromClass(App.class));}}
