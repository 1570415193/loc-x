#import <Foundation/Foundation.h>
#import "VPNLifecycle.h"
int main(){@autoreleasepool{
 if(WLOCActionForStatus(NEVPNStatusConnected)!=WLOCUseConnected){puts("FAIL already connected VPN must be reused, not stopped");return 1;}
 NSCAssert(WLOCActionForStatus(NEVPNStatusConnecting)==WLOCWaitConnecting,@"wait for current startup");
 NSCAssert(WLOCActionForStatus(NEVPNStatusReasserting)==WLOCWaitConnecting,@"wait for reconnect");
 NSCAssert(WLOCActionForStatus(NEVPNStatusDisconnecting)==WLOCWaitDisconnecting,@"wait for disconnect");
 NSCAssert(WLOCActionForStatus(NEVPNStatusDisconnected)==WLOCStartDisconnected,@"start disconnected provider");
 NSCAssert(!WLOCShouldCancelAfterTimeout(NEVPNStatusConnected),@"status-message timeout must not tear down a connected VPN");
 NSCAssert(WLOCShouldCancelAfterTimeout(NEVPNStatusConnecting),@"cancel a startup that never connects");
 NSCAssert(WLOCShouldRecheckOnForeground(NEVPNStatusConnected,YES,NO),@"manual connect while backgrounded must be rechecked before stale timeout");NSCAssert(WLOCShouldRecheckOnForeground(NEVPNStatusConnected,NO,YES),@"restore confirmed session state after settings return");NSCAssert(!WLOCShouldRecheckOnForeground(NEVPNStatusConnected,NO,NO),@"do not apply an unselected position");NSCAssert(!WLOCShouldRecheckOnForeground(NEVPNStatusDisconnected,YES,YES),@"never mask real disconnection");puts("PASS production VPN lifecycle policy: reuse connected, wait in-flight connection, preserve connected on message timeout");}}
