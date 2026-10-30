#import <Foundation/Foundation.h>

/* Finds Android TVs on the Wi-Fi: Bonjour (_androidtvremote2._tcp) plus a sweep of the local /24 for the remote port. */
@interface TVDiscovery : NSObject
@property (nonatomic, readonly) NSArray *found;             /* dictionaries: @"name", @"host" */
@property (nonatomic, readonly) BOOL scanning;
@property (nonatomic, copy) void (^onChange)(void);
- (void)start;
- (void)stop;
@end
