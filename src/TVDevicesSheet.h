#import <UIKit/UIKit.h>

/* The "TVs" panel: saved and discovered TVs, scanning, adding by address, and the pairing dialogue. */
@interface TVDevicesSheet : UIView
@property (nonatomic, copy) void (^onClose)(void);
+ (TVDevicesSheet *)showInView:(UIView *)parent;
- (void)pair:(NSDictionary *)tv;            /* starts pairing with a TV dictionary (name, host) */
- (void)dismiss;
@end
