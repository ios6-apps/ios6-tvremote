#import <Foundation/Foundation.h>

/* Pairing handshake on the TV's pairing port. The TV shows a 6-character code; submitting it proves we saw the same keys as the TV. */
@interface TVPairing : NSObject
@property (nonatomic, copy) void (^onNeedCode)(void);              /* the TV is showing the code now */
@property (nonatomic, copy) void (^onBadCode)(void);               /* a mistyped code: the pairing stays open, submit again */
@property (nonatomic, copy) void (^onDone)(void);
@property (nonatomic, copy) void (^onFailed)(NSString *reason);
- (void)startWithHost:(NSString *)host;                            /* "ip" or "ip:remotePort"; pairing port is remotePort + 1 */
- (void)submitCode:(NSString *)code;
- (void)cancel;
/* the secret for a code, or nil when the code is malformed or its check byte is wrong. Exposed for tests. */
+ (NSData *)secretForCode:(NSString *)code clientModulus:(NSData *)cm clientExponent:(NSData *)ce serverModulus:(NSData *)sm serverExponent:(NSData *)se;
@end
