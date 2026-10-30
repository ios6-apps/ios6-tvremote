#import <Foundation/Foundation.h>

/* Persistent state: our client identity (made once, the TV remembers it after pairing) and the list of TVs. A TV is a dictionary:
   @"name", @"host" (may be "ip" or "ip:port" where port is the remote port; pairing uses port + 1), @"paired" (NSNumber). */
@interface TVStore : NSObject
+ (TVStore *)shared;
@property (nonatomic, readonly) NSString *certPem, *keyPem;       /* nil until an identity exists */
@property (nonatomic, readonly) BOOL making;
/* makes the identity on a background thread if needed; done(nil) when it is there */
- (void)ensureIdentity:(void (^)(NSString *error))done;

@property (nonatomic, readonly) NSArray *tvs;
@property (nonatomic, copy) NSString *currentHost;
- (NSDictionary *)tvForHost:(NSString *)host;
- (void)saveTV:(NSDictionary *)tv;                 /* adds or replaces by host */
- (void)removeTV:(NSString *)host;
+ (NSString *)hostOnly:(NSString *)host;           /* "1.2.3.4:6466" -> "1.2.3.4" */
+ (int)remotePort:(NSString *)host;                /* 6466 unless the host carries a port */
@end
