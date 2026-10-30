#import "TVRemote.h"
#import "TVLink.h"
#import "TVProto.h"
#import "TVStore.h"

NSString *const TVRemoteChanged = @"TVRemoteChanged";

/* remote.proto RemoteMessage field numbers */
enum { F_CONFIGURE = 1, F_SET_ACTIVE = 2, F_ERROR = 3, F_PING_REQ = 8, F_PING_RESP = 9, F_KEY = 10, F_IME_KEY = 20, F_START = 40, F_VOLUME = 50, F_APP_LINK = 90 };
enum { DIR_START_LONG = 1, DIR_END_LONG = 2, DIR_SHORT = 3 };
/* what we ask the TV to keep telling us: ping, keys, ime (current app), power, volume, app links */
enum { FEATURES = 1 | 2 | 4 | 32 | 64 | 512 };

@interface TVRemote ()
@property (nonatomic) TVState state;
@property (nonatomic, copy) NSString *host, *lastError, *deviceName, *currentApp;
@property (nonatomic) BOOL tvOn, muted, unpaired;
@property (nonatomic) int volume, volumeMax;
@property (nonatomic, strong) TVLink *link;
@property (nonatomic) NSInteger generation;
@end

@implementation TVRemote

+ (TVRemote *)shared {
    static TVRemote *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[TVRemote alloc] init]; });
    return s;
}

- (void)changed { [[NSNotificationCenter defaultCenter] postNotificationName:TVRemoteChanged object:self]; }

- (void)connectToHost:(NSString *)host {
    if ([host isEqualToString:self.host] && (self.state == TVStateReady || self.state == TVStateConnecting)) return;
    [self disconnect];
    self.host = host;
    self.unpaired = NO;
    [self open];
}

- (void)disconnect {
    self.generation++;
    [self.link close]; self.link = nil;
    self.host = nil; self.state = TVStateIdle; self.lastError = nil; self.deviceName = nil; self.currentApp = nil;
    self.volume = self.volumeMax = 0; self.muted = NO; self.tvOn = NO;
    [self changed];
}

- (void)reconnect {
    if (!self.host || self.state == TVStateConnecting) return;
    if (self.state == TVStateReady && self.link.open) return;
    [self open];
}

- (void)open {
    NSString *host = self.host;
    TVStore *st = [TVStore shared];
    if (!st.certPem) { self.state = TVStateFailed; self.lastError = @"No identity yet."; [self changed]; return; }
    NSInteger gen = ++self.generation;
    [self.link close];
    self.state = TVStateConnecting; self.lastError = nil;
    [self changed];
    TVLink *link = [[TVLink alloc] init];
    self.link = link;
    __weak TVRemote *me = self;
    link.onMessage = ^(NSData *raw) { if (me.generation == gen) [me handle:raw]; };
    link.onClose = ^(NSString *reason) { if (me.generation == gen) [me lost:reason]; };
    [link connectToHost:[TVStore hostOnly:host] port:[TVStore remotePort:host] cert:st.certPem key:st.keyPem done:^(NSString *err) {
        if (me.generation != gen) return;
        if (err) [me lost:err];
    }];
}

/* the connection dropped or never came up; try again in a few seconds unless the TV says we are not paired */
- (void)lost:(NSString *)reason {
    self.link = nil;
    self.state = TVStateFailed;
    self.lastError = reason ?: @"The TV closed the connection.";
    if ([reason rangeOfString:@"certificate"].location != NSNotFound || [reason rangeOfString:@"alert"].location != NSNotFound) self.unpaired = YES;
    [self changed];
    NSInteger gen = self.generation;
    if (self.unpaired) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.generation == gen && self.host && self.state == TVStateFailed) [self open];
    });
}

- (void)handle:(NSData *)raw {
    NSDictionary *m = TVPBParse(raw);
    if (!m) return;
    NSData *sub;
    if ((sub = TVPBFirstData(m, F_CONFIGURE))) {
        NSDictionary *cfg = TVPBParse(sub);
        NSDictionary *info = TVPBParse(TVPBFirstData(cfg, 2) ?: [NSData data]);
        NSString *vendor = TVPBFirstString(info, 2), *model = TVPBFirstString(info, 1);
        self.deviceName = [[NSString stringWithFormat:@"%@ %@", vendor ?: @"", model ?: @""] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        unsigned long long supported = TVPBFirstNumber(cfg, 1).unsignedLongLongValue;
        NSMutableData *di = [NSMutableData data];
        TVPBVarint(di, 3, 1); TVPBString(di, 4, @"1"); TVPBString(di, 5, @"atvremote"); TVPBString(di, 6, @"1.0.0");
        NSMutableData *c = [NSMutableData data];
        TVPBVarint(c, 1, supported & FEATURES);
        TVPBMessage(c, 2, di);
        NSMutableData *out = [NSMutableData data];
        TVPBMessage(out, F_CONFIGURE, c);
        [self.link send:out];
    } else if ((sub = TVPBFirstData(m, F_SET_ACTIVE))) {
        NSMutableData *a = [NSMutableData data];
        TVPBVarint(a, 1, FEATURES);
        NSMutableData *out = [NSMutableData data];
        TVPBMessage(out, F_SET_ACTIVE, a);
        [self.link send:out];
    } else if ((sub = TVPBFirstData(m, F_PING_REQ))) {
        NSMutableData *p = [NSMutableData data];
        TVPBVarint(p, 1, TVPBFirstNumber(TVPBParse(sub), 1).unsignedLongLongValue);
        NSMutableData *out = [NSMutableData data];
        TVPBMessage(out, F_PING_RESP, p);
        [self.link send:out];
    } else if ((sub = TVPBFirstData(m, F_START))) {
        self.tvOn = TVPBFirstNumber(TVPBParse(sub), 1).boolValue;
        self.state = TVStateReady; self.lastError = nil;
        [self changed];
    } else if ((sub = TVPBFirstData(m, F_VOLUME))) {
        NSDictionary *v = TVPBParse(sub);
        self.volumeMax = TVPBFirstNumber(v, 6).intValue;
        self.volume = TVPBFirstNumber(v, 7).intValue;
        self.muted = TVPBFirstNumber(v, 8).boolValue;
        [self changed];
    } else if ((sub = TVPBFirstData(m, F_IME_KEY))) {
        NSDictionary *info = TVPBParse(TVPBFirstData(TVPBParse(sub), 1) ?: [NSData data]);
        NSString *pkg = TVPBFirstString(info, 12);
        if (pkg && ![pkg isEqualToString:self.currentApp]) { self.currentApp = pkg; [self changed]; }
    } else if (TVPBFirstData(m, F_ERROR)) {
        self.lastError = @"The TV reported an error.";
        [self changed];
    }
}

- (BOOL)ready { return self.state == TVStateReady && self.link.open; }

- (void)inject:(int)code direction:(int)dir {
    NSMutableData *k = [NSMutableData data];
    TVPBVarint(k, 1, (unsigned)code); TVPBVarint(k, 2, (unsigned)dir);
    NSMutableData *out = [NSMutableData data];
    TVPBMessage(out, F_KEY, k);
    [self.link send:out];
}

- (BOOL)sendKey:(int)code { if (![self ready]) return NO; [self inject:code direction:DIR_SHORT]; return YES; }
- (void)holdKey:(int)code down:(BOOL)down { if ([self ready]) [self inject:code direction:down ? DIR_START_LONG : DIR_END_LONG]; }

- (BOOL)launchApp:(NSString *)link {
    if (![self ready]) return NO;
    NSMutableData *a = [NSMutableData data];
    TVPBString(a, 1, link);
    NSMutableData *out = [NSMutableData data];
    TVPBMessage(out, F_APP_LINK, a);
    [self.link send:out];
    return YES;
}

@end
