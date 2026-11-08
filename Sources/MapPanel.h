#import <WebKit/WebKit.h>
@interface MapPanel : UIView <WKScriptMessageHandler, WKNavigationDelegate>
@property(nonatomic,strong) WKWebView *web;
@property(nonatomic,copy) void (^selection)(double latitude,double longitude);
@property(nonatomic,copy) void (^diagnostic)(NSString *message);
@property(nonatomic,copy) void (^notice)(NSString *message);
@property(nonatomic) BOOL tilesVisible;
@property(nonatomic) NSInteger currentSource;
@property(nonatomic) NSArray *pendingPoint;
@property(nonatomic) NSArray *pendingCurrentLocation;
- (void)showLatitude:(double)latitude longitude:(double)longitude selected:(BOOL)selected;
- (void)showCurrentLatitude:(double)latitude longitude:(double)longitude accuracy:(double)accuracy;
- (void)source:(NSInteger)index;
- (void)retry;
@end
