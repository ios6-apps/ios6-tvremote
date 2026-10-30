#import <Foundation/Foundation.h>

/* One TLS connection to the TV carrying length-prefixed protobuf messages. Reading runs on its own thread; the callbacks arrive on the main queue. */
@interface TVLink : NSObject
@property (nonatomic, copy) void (^onMessage)(NSData *msg);
@property (nonatomic, copy) void (^onClose)(NSString *reason);        /* reason is nil for a clean end of stream */
@property (nonatomic, readonly) BOOL open;
/* certPem / keyPem: our client identity. done gets nil on success. Call from the main queue. */
- (void)connectToHost:(NSString *)host port:(int)port cert:(NSString *)cert key:(NSString *)key done:(void (^)(NSString *error))done;
- (void)send:(NSData *)msg;
- (void)close;
/* RSA parts of the TV's certificate (valid once connected) and of our own */
- (BOOL)peerModulus:(NSData **)mod exponent:(NSData **)exp;
@end

BOOL TVCertParts(NSString *certPem, NSData **mod, NSData **exp);
