#import <UIKit/UIKit.h>
#import "TVMainController.h"
#import "TVRemote.h"
#import "TVStore.h"
#import "TVDevicesSheet.h"

@interface TVAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) TVMainController *main;
@end

@implementation TVAppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
#ifdef TV_PREVIEW
    if (getenv("TV_PAGE")) [[NSUserDefaults standardUserDefaults] setInteger:atoi(getenv("TV_PAGE")) forKey:@"page"];
#endif
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.main = [[TVMainController alloc] init];
    self.window.rootViewController = self.main;
    [self.window makeKeyAndVisible];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(remoteChanged) name:TVRemoteChanged object:nil];
#ifdef TV_PREVIEW
    /* the simulator build points at a mock TV on this Mac so the screens can be seen with live data */
    if (getenv("TV_PAIR_HOST")) {
        NSString *h = [NSString stringWithUTF8String:getenv("TV_PAIR_HOST")];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            TVDevicesSheet *s = [TVDevicesSheet showInView:self.main.view];
            [s pair:[NSDictionary dictionaryWithObjectsAndKeys:@"Android TV", @"name", h, @"host", nil]];
        });
    }
    if (getenv("TV_MOCK")) {
        NSString *h = [NSString stringWithUTF8String:getenv("TV_MOCK")];
        [[TVStore shared] saveTV:[NSDictionary dictionaryWithObjectsAndKeys:@"Living Room TV", @"name", h, @"host", [NSNumber numberWithBool:YES], @"paired", nil]];
        [TVStore shared].currentHost = h;
    }
#endif
    [[TVStore shared] ensureIdentity:^(NSString *err) {
        NSString *host = [TVStore shared].currentHost;
        if (!err && host && [[TVStore shared] tvForHost:host]) [[TVRemote shared] connectToHost:host];
        else if (![[TVStore shared] tvs].count) [self.main openDevices];       /* first run: go straight to finding a TV */
    }];
    return YES;
}

/* the TV tells us its real name once connected; keep it */
- (void)remoteChanged {
    TVRemote *r = [TVRemote shared];
    if (r.state == TVStateReady && r.deviceName.length && r.host) {
        NSDictionary *d = [[TVStore shared] tvForHost:r.host];
        if (d && ![[d objectForKey:@"name"] isEqualToString:r.deviceName]) {
            NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary:d];
            [m setObject:r.deviceName forKey:@"name"];
            [[TVStore shared] saveTV:m];
        }
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)app { [[TVRemote shared] reconnect]; }

@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([TVAppDelegate class])); }
}
