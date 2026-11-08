#import <Foundation/Foundation.h>
#import <math.h>
static inline NSDictionary *WLOCValidatedTarget(id value){
 if(![value isKindOfClass:NSDictionary.class])return nil;
 id lat=value[@"latitude"],lon=value[@"longitude"];
 if(![lat isKindOfClass:NSNumber.class]||![lon isKindOfClass:NSNumber.class])return nil;
 double a=[lat doubleValue],b=[lon doubleValue];
 return isfinite(a)&&isfinite(b)&&fabs(a)<=90&&fabs(b)<=180?@{@"latitude":lat,@"longitude":lon}:nil;
}
// Explicit start options must be valid; an invalid explicit target must not silently
// connect with an older position. Manual system starts use the extension's last target.
static inline NSDictionary *WLOCInitialTarget(NSDictionary *options,id saved,id configured){
 if(options[@"target"]!=nil)return WLOCValidatedTarget(options[@"target"]);
 return WLOCValidatedTarget(saved)?:WLOCValidatedTarget(configured);
}

static inline NSString *WLOCValidatedControlToken(id token){if(![token isKindOfClass:NSString.class]||[token length]!=64)return nil;NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"]invertedSet];return [token rangeOfCharacterFromSet:invalid].location==NSNotFound?token:nil;}
