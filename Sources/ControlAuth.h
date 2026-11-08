#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
static inline NSString *WLOCControlMAC(NSString *key,NSString *prefix,NSData *body){NSMutableData *data=[[prefix dataUsingEncoding:NSUTF8StringEncoding]mutableCopy];[data appendData:body];NSData *secret=[key dataUsingEncoding:NSUTF8StringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CCHmac(kCCHmacAlgSHA256,secret.bytes,secret.length,data.bytes,data.length,digest);NSMutableString *s=[NSMutableString string];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",digest[i]];return s;}
static inline BOOL WLOCEqualMAC(NSString *a,NSString *b){NSData *x=[a dataUsingEncoding:NSUTF8StringEncoding],*y=[b dataUsingEncoding:NSUTF8StringEncoding];if(x.length!=64||y.length!=64)return NO;const unsigned char *p=x.bytes,*q=y.bytes;unsigned char difference=0;for(NSUInteger i=0;i<64;i++)difference|=p[i]^q[i];return difference==0;}
