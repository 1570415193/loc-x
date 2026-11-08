#import <Foundation/Foundation.h>
#import "Proxy.h"
#import "LocalControl.h"
#import "ControlAuth.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
static int Connect(int port){int fd=socket(AF_INET,SOCK_STREAM,0);struct sockaddr_in a={.sin_len=sizeof(a),.sin_family=AF_INET,.sin_port=htons(port),.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};if(connect(fd,(void *)&a,sizeof(a))!=0){close(fd);return -1;}return fd;}
static int Raw(NSData *data){int fd=Connect(8878);if(fd<0)return 0;send(fd,data.bytes,data.length,0);char buffer[8192];ssize_t n=recv(fd,buffer,sizeof(buffer),0);close(fd);if(n<=0)return 0;NSString *line=[[NSString alloc]initWithBytes:buffer length:n encoding:NSUTF8StringEncoding];NSArray *parts=[line componentsSeparatedByString:@" "];return parts.count>1?[parts[1]intValue]:0;}
static NSData *Packet(NSString *token,NSString *nonce,NSData *body){NSString *stamp=[NSString stringWithFormat:@"%lld",(long long)NSDate.date.timeIntervalSince1970];NSString *mac=WLOCControlMAC(token,[NSString stringWithFormat:@"WLOC-Request\n%@\n%@\n",nonce,stamp],body);NSString *head=[NSString stringWithFormat:@"POST /wloc/control HTTP/1.1\r\nX-WLOC-Nonce: %@\r\nX-WLOC-Time: %@\r\nX-WLOC-MAC: %@\r\nContent-Length: %lu\r\n\r\n",nonce,stamp,mac,(unsigned long)body.length];NSMutableData *data=[[head dataUsingEncoding:NSUTF8StringEncoding]mutableCopy];[data appendData:body];return data;}
int main(){@autoreleasepool{
 NSString *token=@"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",*wrong=@"abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";
 WLOCProxy *p=[[WLOCProxy alloc]initWithSettings:@{@"latitude":@30,@"longitude":@120}];p.controlToken=token;NSError *error=nil;
 if(![p start:&error]){NSLog(@"FAIL start %@ %ld",error.domain,(long)error.code);return 1;}
 NSDictionary *status=WLOCControlRequest(token,@{@"action":@"status"},&error);NSCAssert(status&&![status[@"ready"]boolValue],@"not-ready must not claim success");p.ready=YES;
 NSCAssert(!WLOCControlRequest(wrong,@{@"action":@"status"},&error)&&error.code==401,@"wrong token rejected by real listener");
 NSDictionary *target=@{@"latitude":@31.2304,@"longitude":@121.4737};NSDictionary *updated=WLOCControlRequest(token,@{@"action":@"target",@"target":target,@"sequence":@2},&error);NSCAssert([updated[@"updated"]boolValue]&&[updated[@"target"]isEqual:target]&&[updated[@"ready"]boolValue],@"actual proxy confirms target");
 NSCAssert(!WLOCControlRequest(token,@{@"action":@"target",@"target":@{@"latitude":@91,@"longitude":@1},@"sequence":@3},&error)&&error.code==400,@"invalid target rejected");
 NSCAssert(!WLOCControlRequest(token,@{@"action":@"target",@"target":@{@"latitude":@10,@"longitude":@20},@"sequence":@1},&error)&&error.code==409,@"out-of-order update cannot restore stale target");
 NSCAssert([WLOCControlRequest(token,@{@"action":@"status"},&error)[@"target"]isEqual:target],@"failed updates leave target intact");
 NSData *body=[NSJSONSerialization dataWithJSONObject:@{@"action":@"status"} options:0 error:nil];NSData *wire=Packet(token,@"00000000000000000000000000000001",body);NSCAssert(Raw(wire)==200&&Raw(wire)==401,@"replayed request rejected");NSString *text=[[NSString alloc]initWithData:wire encoding:NSUTF8StringEncoding];NSCAssert(![text containsString:token],@"secret never sent over loopback");
 int sockets[3];for(int i=0;i<3;i++)sockets[i]=Connect(8877);usleep(100000);NSCAssert(WLOCControlRequest(token,@{@"action":@"status"},&error)!=nil,@"control remains responsive while data proxy slots are occupied");for(int i=0;i<3;i++)if(sockets[i]>=0)close(sockets[i]);
 [p stop];
 int fake=socket(AF_INET,SOCK_STREAM,0),yes=1;setsockopt(fake,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));struct sockaddr_in a={.sin_len=sizeof(a),.sin_family=AF_INET,.sin_port=htons(8878),.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};NSCAssert(bind(fake,(void *)&a,sizeof(a))==0&&listen(fake,1)==0,@"fake listener for response-authentication regression");dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{int peer=accept(fake,NULL,NULL);char bytes[4096];recv(peer,bytes,sizeof(bytes),0);NSString *json=@"{\"controlAPI\":1,\"ready\":true}";NSString *response=[NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Length: %lu\r\n\r\n%@",(unsigned long)[json lengthOfBytesUsingEncoding:NSUTF8StringEncoding],json];NSData *d=[response dataUsingEncoding:NSUTF8StringEncoding];send(peer,d.bytes,d.length,0);close(peer);});NSCAssert(!WLOCControlRequest(token,@{@"action":@"status"},&error)&&[error.domain isEqual:@"WLOC Control Authentication"],@"fake local listener cannot forge successful state");close(fake);puts("PASS actual proxy/control integration: mutual authentication, readiness, target confirmation, invalid/stale writes rejected, independent control capacity");
}}
