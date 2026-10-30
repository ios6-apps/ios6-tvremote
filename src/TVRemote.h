#import <Foundation/Foundation.h>

extern NSString *const TVRemoteChanged;     /* posted on the main queue when state changes */

typedef NS_ENUM(NSInteger, TVState) { TVStateIdle, TVStateConnecting, TVStateReady, TVStateFailed };

/* A live session with a paired TV (remote port 6466). Reconnects by itself while it has a host. */
@interface TVRemote : NSObject
+ (TVRemote *)shared;
@property (nonatomic, readonly) TVState state;
@property (nonatomic, readonly, copy) NSString *host, *lastError;
@property (nonatomic, readonly, copy) NSString *deviceName, *currentApp;
@property (nonatomic, readonly) BOOL tvOn;
@property (nonatomic, readonly) int volume, volumeMax;      /* 0 when the TV did not tell */
@property (nonatomic, readonly) BOOL muted;
@property (nonatomic, readonly) BOOL unpaired;               /* the TV no longer knows us: pair again */

- (void)connectToHost:(NSString *)host;                    /* "ip" or "ip:port" */
- (void)disconnect;
- (void)reconnect;                                         /* e.g. when the app comes to the foreground */
- (BOOL)sendKey:(int)keyCode;                              /* press and release; NO when not connected */
- (void)holdKey:(int)keyCode down:(BOOL)down;              /* for keys that repeat while held */
- (BOOL)launchApp:(NSString *)link;
@end
