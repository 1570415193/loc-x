#import "Proxy.h"
#import "TargetSettings.h"
#import "ControlAuth.h"
#import <TargetConditionals.h>
#import <Security/SecureTransport.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <errno.h>
static NSArray *Domains(void) { return @[@"gs-loc.apple.com",@"gs-loc-cn.apple.com",@"gsp-ssl.ls.apple.com",@"bluedot.is.autonavi.com",@"bluedot.is.autonavi.com.gds.alibabadns.com"]; }
static OSStatus R(SSLConnectionRef c,void *b,size_t *n){ssize_t r=recv((int)(intptr_t)c,b,*n,0);if(r>0){*n=r;return noErr;}*n=0;return r==0?errSSLClosedGraceful:errSSLClosedAbort;}
static OSStatus W(SSLConnectionRef c,const void *b,size_t *n){ssize_t r=send((int)(intptr_t)c,b,*n,0);if(r>0){*n=r;return noErr;}*n=0;return errSSLClosedAbort;}
static BOOL WriteAll(int fd,SSLContextRef ssl,NSData *d){size_t p=0;while(p<d.length){size_t n=d.length-p;OSStatus s=ssl?SSLWrite(ssl,(const char *)d.bytes+p,n,&n):W((void *)(intptr_t)fd,(const char *)d.bytes+p,&n);if(s!=noErr||!n)return NO;p+=n;}return YES;}
static NSData *ReadSome(int fd,SSLContextRef ssl){char b[8192];size_t n=sizeof(b);OSStatus s=ssl?SSLRead(ssl,b,n,&n):R((void *)(intptr_t)fd,b,&n);if(n)return [NSData dataWithBytes:b length:n];return nil;}
static NSDictionary *ReadRequestLimited(int fd,SSLContextRef ssl,NSUInteger limit){NSMutableData *data=[NSMutableData data];NSData *sep=[@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];NSRange end;
 while((end=[data rangeOfData:sep options:0 range:NSMakeRange(0,data.length)]).location==NSNotFound){NSData *b=ReadSome(fd,ssl);if(!b||data.length+b.length>65536)return nil;[data appendData:b];}
 NSUInteger offset=NSMaxRange(end);NSString *header=[[NSString alloc]initWithData:[data subdataWithRange:NSMakeRange(0,end.location)] encoding:NSISOLatin1StringEncoding];NSArray *lines=[header componentsSeparatedByString:@"\r\n"];NSArray *first=[lines[0] componentsSeparatedByString:@" "];if(first.count!=3)return nil;NSMutableDictionary *headers=[NSMutableDictionary dictionary];
 for(NSUInteger i=1;i<lines.count;i++){NSString *l=lines[i];NSRange c=[l rangeOfString:@":"];if(c.location==NSNotFound)return nil;NSString *key=[[l substringToIndex:c.location] lowercaseString];if(headers[key])return nil;headers[key]=[[l substringFromIndex:c.location+1]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];}
 if(headers[@"transfer-encoding"])return nil;NSString *len=headers[@"content-length"]?:@"0";NSScanner *scan=[NSScanner scannerWithString:len];long long length=0;if(![scan scanLongLong:&length]||!scan.isAtEnd||length<0||length>limit)return nil;
 while(data.length-offset<(NSUInteger)length){NSData *b=ReadSome(fd,ssl);if(!b)return nil;[data appendData:b];}
 return @{@"method":first[0],@"target":first[1],@"headers":headers,@"body":[data subdataWithRange:NSMakeRange(offset,(NSUInteger)length)]};}
static NSDictionary *ReadRequest(int fd,SSLContextRef ssl){return ReadRequestLimited(fd,ssl,2*1024*1024);}
@interface WLOCProxy () <NSURLSessionTaskDelegate>
@property NSDictionary *settings;
@property NSArray *certificates;
@property int listener,controlListener;
@property NSUInteger revision;
@property NSMutableDictionary<NSString *,NSNumber *> *controlNonces;
@property BOOL stopped;
@property dispatch_queue_t queue;
@property dispatch_semaphore_t slots;
@property NSMutableSet<NSNumber *> *clients;
@property NSUInteger requests,patched,failures;
@property NSString *last;
@end
@implementation WLOCProxy
- (instancetype)initWithSettings:(NSDictionary *)s{if((self=[super init])){_settings=s;_controlNonces=[NSMutableDictionary dictionary];_listener=-1;_controlListener=-1;_clients=[NSMutableSet set];_last=@"尚无请求";_queue=dispatch_queue_create("wloc.proxy",DISPATCH_QUEUE_CONCURRENT);_slots=dispatch_semaphore_create(3);}return self;}
- (void)note:(NSString *)s failed:(BOOL)failed{@synchronized(self){self.last=s;if(failed)self.failures++;}}
- (NSDictionary *)status{@synchronized(self){return @{@"controlAPI":@1,@"ready":@(self.ready),@"revision":@(self.revision),@"sequence":@(self.controlSequence),@"target":self.settings?:@{},@"requests":@(self.requests),@"patched":@(self.patched),@"failures":@(self.failures),@"last":self.last?:@""};}}
- (BOOL)start:(NSError **)error{
 if(!WLOCValidatedControlToken(self.controlToken)){if(error)*error=[NSError errorWithDomain:@"WLOC control token" code:401 userInfo:nil];return NO;}
 NSData *p12=[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"server" ofType:@"p12"]];NSString *password=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"p12-password" ofType:@"txt"] encoding:NSUTF8StringEncoding error:nil];CFArrayRef items=NULL;NSMutableDictionary *importOptions=[@{(__bridge id)kSecImportExportPassphrase:password?:@""}mutableCopy];
#if TARGET_OS_OSX
 if(@available(macOS 15.0,*))importOptions[(__bridge id)kSecImportToMemoryOnly]=@YES;
#endif
 OSStatus status=SecPKCS12Import((__bridge CFDataRef)p12,(__bridge CFDictionaryRef)importOptions,&items);
 if(status!=errSecSuccess){if(error)*error=[NSError errorWithDomain:@"WLOC TLS identity" code:status userInfo:nil];return NO;}NSArray *a=CFBridgingRelease(items);NSDictionary *item=a.firstObject;SecIdentityRef identity=(__bridge SecIdentityRef)item[(__bridge id)kSecImportItemIdentity];SecCertificateRef leaf=NULL;SecIdentityCopyCertificate(identity,&leaf);self.certificates=@[(__bridge id)identity];if(leaf)CFRelease(leaf);
 int fd=socket(AF_INET,SOCK_STREAM,0);int yes=1;setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));struct sockaddr_in address={.sin_len=sizeof(address),.sin_family=AF_INET,.sin_port=htons(8877),.sin_addr.s_addr=htonl(INADDR_LOOPBACK)};
 if(fd<0||bind(fd,(void *)&address,sizeof(address))||listen(fd,8)){int code=errno;if(fd>=0)close(fd);if(error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];return NO;}self.listener=fd;
 int control=socket(AF_INET,SOCK_STREAM,0);setsockopt(control,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof(yes));address.sin_port=htons(8878);if(control<0||bind(control,(void *)&address,sizeof(address))||listen(control,4)){int code=errno;if(control>=0)close(control);close(fd);self.listener=-1;if(error)*error=[NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];return NO;}self.controlListener=control;dispatch_semaphore_t controlSlots=dispatch_semaphore_create(2);
 for(NSNumber *number in @[@(fd),@(control)]){int server=number.intValue;BOOL isControl=server==control;dispatch_async(self.queue,^{while(!self.stopped){int c=accept(server,NULL,NULL);if(c<0)break;dispatch_semaphore_t slots=isControl?controlSlots:self.slots;if(dispatch_semaphore_wait(slots,DISPATCH_TIME_NOW)!=0){close(c);continue;}struct timeval tv={isControl?3:20,0};setsockopt(c,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));setsockopt(c,SOL_SOCKET,SO_SNDTIMEO,&tv,sizeof(tv));setsockopt(c,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));@synchronized(self){[self.clients addObject:@(c)];}dispatch_async(self.queue,^{@autoreleasepool{if(isControl)[self handleControl:c];else [self handle:c];@synchronized(self){[self.clients removeObject:@(c)];}close(c);dispatch_semaphore_signal(slots);}});}});}
 return YES;
}
- (BOOL)updateSettings:(NSDictionary *)settings{NSDictionary *target=WLOCValidatedTarget(settings);if(!target)return NO;@synchronized(self){if(![self.settings isEqualToDictionary:target]){self.settings=target;self.revision++;self.requests=0;self.patched=0;self.failures=0;}self.last=@"目标已更新，等待下一次网络定位请求";}if(self.targetDidChange)self.targetDidChange(target);return YES;}
- (void)handleControl:(int)fd{
 NSDictionary *request=ReadRequestLimited(fd,NULL,4096);NSString *nonce=request[@"headers"][@"x-wloc-nonce"],*stamp=request[@"headers"][@"x-wloc-time"],*provided=request[@"headers"][@"x-wloc-mac"];NSData *payload=request[@"body"]?:NSData.data;BOOL authenticated=nonce.length==32&&stamp.length>0&&stamp.length<16&&[stamp rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location==NSNotFound&&fabs(NSDate.date.timeIntervalSince1970-stamp.longLongValue)<=30&&WLOCEqualMAC(provided,WLOCControlMAC(self.controlToken?:@"",[NSString stringWithFormat:@"WLOC-Request\n%@\n%@\n",nonce,stamp],payload));
 if(authenticated){@synchronized(self){for(NSString *old in self.controlNonces.allKeys)if(NSDate.date.timeIntervalSince1970-self.controlNonces[old].doubleValue>60)[self.controlNonces removeObjectForKey:old];if(self.controlNonces[nonce])authenticated=NO;else self.controlNonces[nonce]=@(NSDate.date.timeIntervalSince1970);}}
 NSInteger code=200;NSDictionary *reply=nil;if(![request[@"method"]isEqual:@"POST"]||![request[@"target"]isEqual:@"/wloc/control"])code=404;else if(!authenticated)code=401;else {id value=[NSJSONSerialization JSONObjectWithData:request[@"body"] options:0 error:nil];if(![value isKindOfClass:NSDictionary.class])code=400;else if([value[@"action"]isEqual:@"status"])reply=self.status;else if([value[@"action"]isEqual:@"target"]){@synchronized(self){BOOL validSequence=[value[@"sequence"]isKindOfClass:NSNumber.class];unsigned long long sequence=validSequence?[value[@"sequence"]unsignedLongLongValue]:0;if(!validSequence||sequence<=self.controlSequence)code=409;else if([self updateSettings:value[@"target"]]){self.controlSequence=sequence;if(self.sequenceDidChange)self.sequenceDidChange(@(sequence));NSMutableDictionary *updated=[self.status mutableCopy];updated[@"updated"]=@YES;reply=updated;}else code=400;}}else code=400;}
 NSData *body=reply?[NSJSONSerialization dataWithJSONObject:reply options:0 error:nil]:NSData.data;NSString *header=[NSString stringWithFormat:@"HTTP/1.1 %ld Control\r\nContent-Type: application/json\r\nX-WLOC-MAC: %@\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",(long)code,WLOCControlMAC(self.controlToken?:@"",[NSString stringWithFormat:@"WLOC-Response\n%@\n%ld\n",nonce?:@"",(long)code],body),(unsigned long)body.length];WriteAll(fd,NULL,[header dataUsingEncoding:NSUTF8StringEncoding]);WriteAll(fd,NULL,body);
}
- (void)stop{self.stopped=YES;self.ready=NO;if(self.controlListener>=0){shutdown(self.controlListener,SHUT_RDWR);close(self.controlListener);self.controlListener=-1;}if(self.listener>=0){shutdown(self.listener,SHUT_RDWR);close(self.listener);self.listener=-1;}@synchronized(self){for(NSNumber *n in self.clients)shutdown(n.intValue,SHUT_RDWR);}}
- (NSData *)rewrite:(NSData *)body url:(NSString *)url headers:(NSDictionary *)headers{
 NSDictionary *target=nil;NSUInteger revision=0;@synchronized(self){target=self.settings;revision=self.revision;}JSContext *ctx=[JSContext new];__block NSString *exception=nil;ctx.exceptionHandler=^(JSContext *c,JSValue *e){exception=e.toString;};ctx[@"console"]=@{@"log":^(NSString *s){[self note:s failed:NO];}};ctx[@"$script"]=@{@"startTime":@([NSDate date].timeIntervalSince1970)};ctx[@"$environment"]=@{@"surge-version":@"WLOCStandalone"};ctx[@"$argument"]=[NSString stringWithFormat:@"longitude=%.8f&latitude=%.8f&accuracy=25&logLevel=info",[target[@"longitude"]doubleValue],[target[@"latitude"]doubleValue]];ctx[@"$persistentStore"]=@{@"read":^id(NSString *key){return (id)nil;}};ctx[@"$request"]=@{@"url":url};
 NSMutableArray *bytes=[NSMutableArray arrayWithCapacity:body.length];const uint8_t *raw=body.bytes;for(NSUInteger i=0;i<body.length;i++)[bytes addObject:@(raw[i])];ctx[@"$response"]=@{@"bodyBytes":bytes,@"headers":headers,@"status":@200};__block NSData *result=nil;__block BOOL done=NO;
 ctx[@"$done"]=^(JSValue *value){JSValue *response=value[@"response"];if(response.isUndefined)response=value;JSValue *b=response[@"bodyBytes"];if(!b.isUndefined){NSUInteger length=[b[@"length"]toUInt32];if(length<=2*1024*1024){NSMutableData *out=[NSMutableData dataWithLength:length];uint8_t *p=out.mutableBytes;for(NSUInteger i=0;i<length;i++)p[i]=(uint8_t)[b[i]toUInt32];result=out;}}done=YES;};
 NSString *script=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"wloc" ofType:@"js"] encoding:NSUTF8StringEncoding error:nil];[ctx evaluateScript:script];NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];while(!done&&!exception&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
 if(exception||!done||!result){[self note:exception?:@"wloc 脚本未完成，保留原响应" failed:YES];return body;}if(![result isEqualToData:body]){@synchronized(self){if(revision==self.revision)self.patched++;}}return result;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler{completionHandler(nil);}
- (void)handle:(int)fd{
 SSLContextRef ssl=NULL;@try{
 NSDictionary *connect=ReadRequest(fd,NULL);NSArray *authority=[connect[@"target"]componentsSeparatedByString:@":"];NSString *host=authority.firstObject;
 if(![connect[@"method"]isEqual:@"CONNECT"]||authority.count!=2||![authority[1]isEqual:@"443"]||![Domains() containsObject:host]){WriteAll(fd,NULL,[@"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]);return;}
 WriteAll(fd,NULL,[@"HTTP/1.1 200 Connection Established\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]);ssl=SSLCreateContext(NULL,kSSLServerSide,kSSLStreamType);SSLSetIOFuncs(ssl,R,W);SSLSetConnection(ssl,(void *)(intptr_t)fd);SSLSetProtocolVersionMin(ssl,kTLSProtocol12);OSStatus certStatus=SSLSetCertificate(ssl,(__bridge CFArrayRef)self.certificates);OSStatus hs=certStatus?:SSLHandshake(ssl);if(hs){[self note:[NSString stringWithFormat:@"TLS 握手失败 %d；检查证书信任和规则状态",(int)hs] failed:YES];return;}
 NSDictionary *req=ReadRequest(fd,ssl);if(!req)return;NSString *path=req[@"target"];if(![path hasPrefix:@"/"]||[path hasPrefix:@"//"]||[path containsString:@"\r"]||[path containsString:@"\n"])return;NSURL *url=[NSURL URLWithString:[NSString stringWithFormat:@"https://%@%@",host,path]];if(!url||![url.host isEqual:host])return;
 @synchronized(self){self.requests++;}NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];request.HTTPMethod=req[@"method"];request.HTTPBody=req[@"body"];
 NSDictionary *headers=req[@"headers"];NSSet *skip=[NSSet setWithArray:@[@"host",@"connection",@"proxy-connection",@"content-length",@"transfer-encoding",@"accept-encoding"]];for(NSString *key in headers)if(![skip containsObject:key])[request setValue:headers[key] forHTTPHeaderField:key];[request setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
 NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;configuration.connectionProxyDictionary=@{(NSString *)kCFNetworkProxiesHTTPEnable:@NO,@"HTTPSEnable":@NO};configuration.HTTPCookieStorage=nil;NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];dispatch_semaphore_t sem=dispatch_semaphore_create(0);__block NSData *body=nil;__block NSHTTPURLResponse *response=nil;__block NSError *err=nil;
 NSURLSessionDataTask *task=[session dataTaskWithRequest:request completionHandler:^(NSData *d,NSURLResponse *r,NSError *e){body=d;response=(id)r;err=e;dispatch_semaphore_signal(sem);}];[task resume];BOOL timed=dispatch_semaphore_wait(sem,dispatch_time(DISPATCH_TIME_NOW,17*NSEC_PER_SEC))!=0;[session invalidateAndCancel];
 if(timed||err||!response){[self note:err.localizedDescription?:@"上游请求超时" failed:YES];WriteAll(fd,ssl,[@"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]);return;}
 if(body.length>2*1024*1024){[self note:@"响应超过处理上限" failed:YES];return;}
 if(response.statusCode==200&&[url.path isEqual:@"/clls/wloc"]){body=[self rewrite:body url:url.absoluteString headers:response.allHeaderFields];}
 NSMutableString *head=[NSMutableString stringWithFormat:@"HTTP/1.1 %ld %@\r\n",(long)response.statusCode,[NSHTTPURLResponse localizedStringForStatusCode:response.statusCode]];
 for(NSString *key in response.allHeaderFields){NSString *lower=key.lowercaseString;if([@[@"content-length",@"content-encoding",@"transfer-encoding",@"connection",@"keep-alive"]containsObject:lower])continue;NSString *v=[response.allHeaderFields[key]description];if([v rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location==NSNotFound)[head appendFormat:@"%@: %@\r\n",key,v];}
 [head appendFormat:@"Content-Length: %lu\r\nConnection: close\r\n\r\n",(unsigned long)body.length];WriteAll(fd,ssl,[head dataUsingEncoding:NSISOLatin1StringEncoding]);WriteAll(fd,ssl,body?:NSData.data);
 }@finally{if(ssl){SSLClose(ssl);CFRelease(ssl);}}
}
@end
