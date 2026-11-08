#import "LocalControl.h"
#import "TargetSettings.h"
#import "ControlAuth.h"
#import <Security/SecRandom.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>
#include <errno.h>
static NSDictionary *Failure(NSError **error,NSString *domain,NSInteger code){if(error)*error=[NSError errorWithDomain:domain code:code userInfo:nil];return nil;}
static NSDictionary *Exchange(NSString *token,NSDictionary *message,NSError **error){
 if(!WLOCValidatedControlToken(token))return Failure(error,@"WLOC Control",401);
 NSData *body=[NSJSONSerialization dataWithJSONObject:message options:0 error:error];if(!body||body.length>4096)return nil;
 int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0)return Failure(error,NSPOSIXErrorDomain,errno);
 @try{int yes=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));struct timeval timeout={2,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));int flags=fcntl(fd,F_GETFL,0);fcntl(fd,F_SETFL,flags|O_NONBLOCK);struct sockaddr_in address={.sin_len=sizeof(address),.sin_family=AF_INET,.sin_port=htons(8878),.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
 if(connect(fd,(void *)&address,sizeof(address))!=0){if(errno!=EINPROGRESS)return Failure(error,NSPOSIXErrorDomain,errno);struct pollfd p={fd,POLLOUT,0};int rc=poll(&p,1,2000);if(rc<=0)return Failure(error,NSPOSIXErrorDomain,rc==0?ETIMEDOUT:errno);int result=0;socklen_t length=sizeof(result);if(getsockopt(fd,SOL_SOCKET,SO_ERROR,&result,&length)!=0||result)return Failure(error,NSPOSIXErrorDomain,result?:errno);}fcntl(fd,F_SETFL,flags);
 uint8_t random[16];if(SecRandomCopyBytes(kSecRandomDefault,sizeof(random),random)!=errSecSuccess)return Failure(error,@"WLOC Control",500);NSMutableString *nonce=[NSMutableString string];for(int i=0;i<16;i++)[nonce appendFormat:@"%02x",random[i]];NSString *stamp=[NSString stringWithFormat:@"%lld",(long long)NSDate.date.timeIntervalSince1970];NSString *mac=WLOCControlMAC(token,[NSString stringWithFormat:@"WLOC-Request\n%@\n%@\n",nonce,stamp],body);NSString *head=[NSString stringWithFormat:@"POST /wloc/control HTTP/1.1\r\nHost: 127.0.0.1:8878\r\nX-WLOC-Nonce: %@\r\nX-WLOC-Time: %@\r\nX-WLOC-MAC: %@\r\nContent-Type: application/json\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",nonce,stamp,mac,(unsigned long)body.length];NSMutableData *request=[[head dataUsingEncoding:NSUTF8StringEncoding]mutableCopy];[request appendData:body];NSUInteger sent=0;while(sent<request.length){ssize_t n=send(fd,(const char *)request.bytes+sent,request.length-sent,0);if(n<=0)return Failure(error,NSPOSIXErrorDomain,errno?:EPIPE);sent+=n;}
 NSMutableData *reply=[NSMutableData data];char bytes[4096];NSTimeInterval end=NSDate.timeIntervalSinceReferenceDate+3;while(reply.length<65536&&NSDate.timeIntervalSinceReferenceDate<end){ssize_t n=recv(fd,bytes,sizeof(bytes),0);if(n==0)break;if(n<0)return Failure(error,NSPOSIXErrorDomain,errno);[reply appendBytes:bytes length:n];}if(reply.length>=65536)return Failure(error,@"WLOC Control",413);
 NSRange split=[reply rangeOfData:[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding] options:0 range:NSMakeRange(0,reply.length)];if(split.location==NSNotFound)return Failure(error,@"WLOC Control",502);NSString *headers=[[NSString alloc]initWithData:[reply subdataWithRange:NSMakeRange(0,split.location)] encoding:NSUTF8StringEncoding];NSArray *line=[headers componentsSeparatedByString:@"\r\n"];NSArray *status=[line.firstObject componentsSeparatedByString:@" "];NSInteger code=status.count>1?[status[1]integerValue]:502;if(code!=200)return Failure(error,@"WLOC Control HTTP",code);
 NSData *json=[reply subdataWithRange:NSMakeRange(NSMaxRange(split),reply.length-NSMaxRange(split))];NSString *responseMAC=nil;for(NSString *field in line){NSRange colon=[field rangeOfString:@":"];if(colon.location!=NSNotFound&&[[[field substringToIndex:colon.location]lowercaseString]isEqual:@"x-wloc-mac"])responseMAC=[[field substringFromIndex:colon.location+1]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];}if(!WLOCEqualMAC(responseMAC,WLOCControlMAC(token,[NSString stringWithFormat:@"WLOC-Response\n%@\n%ld\n",nonce,(long)code],json)))return Failure(error,@"WLOC Control Authentication",401);id value=[NSJSONSerialization JSONObjectWithData:json options:0 error:error];if(![value isKindOfClass:NSDictionary.class]||[value[@"controlAPI"]integerValue]!=1)return Failure(error,@"WLOC Control",426);return value;
 }@finally{close(fd);}
}

NSString *WLOCControlErrorMessage(NSError *error){NSString *message=@"本机代理通信失败";if([error.domain isEqual:NSPOSIXErrorDomain]&&error.code==ECONNREFUSED)message=@"本机代理尚未监听或已退出";else if([error.domain isEqual:NSPOSIXErrorDomain]&&(error.code==ETIMEDOUT||error.code==EAGAIN))message=@"本机代理没有及时回复";else if(error.code==401)message=@"本机代理身份验证失败";else if(error.code==409)message=@"旧坐标命令已被拒绝，请重试本次位置";return [NSString stringWithFormat:@"%@（%@ %ld）",message,error.domain?:@"WLOC Control",(long)error.code];}

NSDictionary *WLOCControlRequest(NSString *token,NSDictionary *message,NSError **error){if([message[@"action"]isEqual:@"target"]){if(!Exchange(token,@{@"action":@"status"},error))return nil;}return Exchange(token,message,error);}
