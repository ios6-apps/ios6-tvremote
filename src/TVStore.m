#import "TVStore.h"
#import "TVTLS.h"

@interface TVStore ()
@property (nonatomic, copy) NSString *certPem, *keyPem;
@property (nonatomic) BOOL making;
@property (nonatomic, strong) NSMutableArray *list;
@property (nonatomic, strong) NSMutableArray *waiting;
@end

@implementation TVStore

+ (TVStore *)shared {
    static TVStore *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[TVStore alloc] init]; });
    return s;
}

- (id)init {
    if ((self = [super init])) {
        NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
        self.certPem = [u stringForKey:@"identityCert"];
        self.keyPem = [u stringForKey:@"identityKey"];
        self.list = [NSMutableArray arrayWithArray:[u arrayForKey:@"tvs"] ?: [NSArray array]];
        self.waiting = [NSMutableArray array];
    }
    return self;
}

- (void)ensureIdentity:(void (^)(NSString *))done {
    if (self.certPem && self.keyPem) { done(nil); return; }
    [self.waiting addObject:[done copy]];
    if (self.making) return;
    self.making = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char cert[2048] = "", key[2048] = "", err[200] = "";
        int r = tv_identity_generate("tvremote-iphone", cert, sizeof cert, key, sizeof key, err, sizeof err);
        NSString *certStr = [NSString stringWithUTF8String:cert], *keyStr = [NSString stringWithUTF8String:key], *errStr = [NSString stringWithUTF8String:err];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.making = NO;
            NSString *error = nil;
            if (r == 0) {
                self.certPem = certStr; self.keyPem = keyStr;
                NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
                [u setObject:self.certPem forKey:@"identityCert"]; [u setObject:self.keyPem forKey:@"identityKey"];
                [u synchronize];
            } else error = errStr;
            NSArray *w = [self.waiting copy];
            [self.waiting removeAllObjects];
            for (void (^cb)(NSString *) in w) cb(error);
        });
    });
}

- (NSArray *)tvs { return self.list; }

- (void)persist {
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    [u setObject:self.list forKey:@"tvs"];
    [u synchronize];
}

- (NSString *)currentHost { return [[NSUserDefaults standardUserDefaults] stringForKey:@"currentHost"]; }
- (void)setCurrentHost:(NSString *)h {
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    if (h) [u setObject:h forKey:@"currentHost"]; else [u removeObjectForKey:@"currentHost"];
    [u synchronize];
}

- (NSDictionary *)tvForHost:(NSString *)host {
    for (NSDictionary *d in self.list) if ([[d objectForKey:@"host"] isEqualToString:host]) return d;
    return nil;
}

- (void)saveTV:(NSDictionary *)tv {
    NSString *host = [tv objectForKey:@"host"];
    for (NSUInteger i = 0; i < self.list.count; i++)
        if ([[[self.list objectAtIndex:i] objectForKey:@"host"] isEqualToString:host]) { [self.list replaceObjectAtIndex:i withObject:tv]; [self persist]; return; }
    [self.list addObject:tv];
    [self persist];
}

- (void)removeTV:(NSString *)host {
    NSDictionary *d = [self tvForHost:host];
    if (d) { [self.list removeObject:d]; [self persist]; }
    if ([self.currentHost isEqualToString:host]) self.currentHost = nil;
}

+ (NSString *)hostOnly:(NSString *)host {
    NSRange r = [host rangeOfString:@":"];
    return r.location == NSNotFound ? host : [host substringToIndex:r.location];
}

+ (int)remotePort:(NSString *)host {
    NSRange r = [host rangeOfString:@":"];
    return r.location == NSNotFound ? 6466 : [[host substringFromIndex:r.location + 1] intValue];
}

@end
