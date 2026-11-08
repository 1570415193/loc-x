#import <NetworkExtension/NetworkExtension.h>
typedef NS_ENUM(NSInteger,WLOCConnectionAction){WLOCStartDisconnected,WLOCUseConnected,WLOCWaitConnecting,WLOCWaitDisconnecting};
static inline WLOCConnectionAction WLOCActionForStatus(NEVPNStatus status){
 if(status==NEVPNStatusConnected)return WLOCUseConnected;
 if(status==NEVPNStatusConnecting||status==NEVPNStatusReasserting)return WLOCWaitConnecting;
 if(status==NEVPNStatusDisconnecting)return WLOCWaitDisconnecting;
 return WLOCStartDisconnected;
}
static inline BOOL WLOCShouldCancelAfterTimeout(NEVPNStatus status){return status!=NEVPNStatusConnected;}

static inline BOOL WLOCShouldRecheckOnForeground(NEVPNStatus status,BOOL pendingTarget,BOOL previouslyConfirmed){return status==NEVPNStatusConnected&&(pendingTarget||previouslyConfirmed);}
