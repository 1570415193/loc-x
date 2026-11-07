#import <NetworkExtension/NetworkExtension.h>
#import "Proxy.h"
@interface Tunnel : NEPacketTunnelProvider
@property WLOCProxy *proxy;
@end
@implementation Tunnel
- (void)startTunnelWithOptions:(NSDictionary *)options completionHandler:(void (^)(NSError *))completionHandler{
 NSDictionary *settings=((NETunnelProviderProtocol *)self.protocolConfiguration).providerConfiguration;
 double lat=[settings[@"latitude"]doubleValue],lon=[settings[@"longitude"]doubleValue];if(!settings[@"latitude"]||!settings[@"longitude"]||!isfinite(lat)||!isfinite(lon)||fabs(lat)>90||fabs(lon)>180){completionHandler([NSError errorWithDomain:@"WLOC 坐标无效" code:1 userInfo:nil]);return;}
 self.proxy=[[WLOCProxy alloc]initWithSettings:settings];NSError *err=nil;if(![self.proxy start:&err]){completionHandler(err);return;}
 NEPacketTunnelNetworkSettings *network=[[NEPacketTunnelNetworkSettings alloc]initWithTunnelRemoteAddress:@"127.0.0.1"];network.IPv4Settings=[[NEIPv4Settings alloc]initWithAddresses:@[@"198.18.0.1"] subnetMasks:@[@"255.255.255.252"]];network.IPv4Settings.includedRoutes=@[];network.IPv4Settings.excludedRoutes=@[[NEIPv4Route defaultRoute]];
 NEProxySettings *proxy=[NEProxySettings new];proxy.HTTPEnabled=YES;proxy.HTTPSEnabled=YES;proxy.HTTPServer=[[NEProxyServer alloc]initWithAddress:@"127.0.0.1" port:8877];proxy.HTTPSServer=proxy.HTTPServer;proxy.matchDomains=@[@"gs-loc.apple.com",@"gs-loc-cn.apple.com",@"gsp-ssl.ls.apple.com",@"bluedot.is.autonavi.com",@"bluedot.is.autonavi.com.gds.alibabadns.com"];proxy.excludeSimpleHostnames=YES;network.proxySettings=proxy;
 __weak Tunnel *weakSelf=self;[self setTunnelNetworkSettings:network completionHandler:^(NSError *e){if(e)[weakSelf.proxy stop];completionHandler(e);}];
}
- (void)stopTunnelWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))completionHandler{[self.proxy stop];self.proxy=nil;completionHandler();}
- (void)handleAppMessage:(NSData *)messageData completionHandler:(void (^)(NSData *))completionHandler{NSDictionary *message=[NSJSONSerialization JSONObjectWithData:messageData options:0 error:nil];NSDictionary *result=self.proxy.status?:@{};if([message[@"action"]isEqual:@"target"])result=@{@"updated":@([self.proxy updateSettings:message[@"target"]])};if(completionHandler)completionHandler([NSJSONSerialization dataWithJSONObject:result options:0 error:nil]);}
@end
