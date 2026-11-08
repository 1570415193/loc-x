#import <Foundation/Foundation.h>
// Only communicates with the authenticated loopback listener, never a remote host.
NSDictionary *WLOCControlRequest(NSString *token,NSDictionary *message,NSError **error);

NSString *WLOCControlErrorMessage(NSError *error);
