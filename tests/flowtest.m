/* Runs the real pairing + remote classes on the Mac against tools/mock_tv.py.
   usage: flowtest HOST:PORT   (the mock must run on that port; it writes the pairing code to $MOCK_CODE_FILE, default /tmp/mock_tv_code)
   Normally started by tests/run.sh, which also checks what the mock saw. */
#import <Foundation/Foundation.h>
#import "TVStore.h"
#import "TVPairing.h"
#import "TVRemote.h"
#import "TVProto.h"

/* the mock writes the code just after it acknowledges the configuration, so it may take a moment to appear */
static NSString *mockCode(void) {
    const char *f = getenv("MOCK_CODE_FILE");
    NSString *path = f ? [NSString stringWithUTF8String:f] : @"/tmp/mock_tv_code";
    for (int i = 0; i < 40; i++) {
        NSString *c = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (c.length == 6) return c;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return @"";
}

static NSString *hex(NSData *d) {
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x", ((const unsigned char *)d.bytes)[i]];
    return s;
}

static void spin(double s) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *host = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"127.0.0.1:7466";
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:@"flowtest"];
        __block BOOL idDone = NO;
        NSDate *t0 = [NSDate date];
        [[TVStore shared] ensureIdentity:^(NSString *e) { printf("identity: %s (%.1fs)\n", e ? e.UTF8String : "ok", -[t0 timeIntervalSinceNow]); idDone = YES; }];
        while (!idDone) spin(0.1);

        /* known-answer test for the pairing secret; the expected values come from tests/secret_ref.py (hashlib) */
        NSData *a = [NSData dataWithBytes:"\x01\x02\x03" length:3], *b = [NSData dataWithBytes:"\x04\x05" length:2];
        NSData *s = [TVPairing secretForCode:@"2DABCD" clientModulus:a clientExponent:b serverModulus:a serverExponent:b];
        if (![hex(s) isEqualToString:@"2d8dff344e67eb663bf5d8176bbb9e4c19f3dc92e9788ab55aab24bf4e7fc513"]) { printf("secret known-answer test FAILED: %s\n", hex(s).UTF8String); return 1; }
        if ([TVPairing secretForCode:@"FFABCD" clientModulus:a clientExponent:b serverModulus:a serverExponent:b]) { printf("a wrong check byte was accepted\n"); return 1; }
        printf("secret known-answer test ok\n");

        __block int stage = 0;
        TVPairing *p = [[TVPairing alloc] init];
        __weak TVPairing *wp = p;   /* the blocks below are retained by p */
        p.onNeedCode = ^{
            NSString *code = mockCode();
            printf("need code, TV shows %s\n", code.UTF8String);
            if (stage == 0) { stage = 1; printf("first a wrong code\n"); [wp submitCode:@"FF0000"]; }
            else [wp submitCode:code];
        };
        p.onBadCode = ^{ printf("bad code detected locally, retrying with the right one\n"); stage = 2; [wp submitCode:mockCode()]; };
        p.onFailed = ^(NSString *r) { printf("PAIRING FAILED: %s\n", r.UTF8String); stage = -1; };
        p.onDone = ^{ printf("PAIRED\n"); stage = 99; };
        [p startWithHost:host];
        for (int i = 0; i < 100 && stage != 99 && stage != -1; i++) spin(0.1);
        if (stage != 99) { printf("pairing did not finish (stage %d)\n", stage); return 1; }

        TVRemote *r = [TVRemote shared];
        [[NSNotificationCenter defaultCenter] addObserverForName:TVRemoteChanged object:r queue:nil usingBlock:^(NSNotification *n) {
            printf("state=%ld name=%s on=%d vol=%d/%d muted=%d app=%s err=%s\n", (long)r.state, r.deviceName.UTF8String, r.tvOn, r.volume, r.volumeMax, r.muted, r.currentApp.UTF8String, r.lastError.UTF8String);
        }];
        [r connectToHost:host];
        for (int i = 0; i < 50 && r.state != TVStateReady; i++) spin(0.1);
        if (r.state != TVStateReady) { printf("remote not ready\n"); return 1; }
        [r sendKey:TVKeyUp]; [r sendKey:TVKeyCenter]; [r holdKey:TVKeyRight down:YES]; spin(0.3); [r holdKey:TVKeyRight down:NO];
        [r launchApp:@"https://www.youtube.com"];
        spin(1.0);
        [r disconnect];
        printf("done\n");
    }
    return 0;
}
