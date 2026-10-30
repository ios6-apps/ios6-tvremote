#import "TVPairing.h"
#import "TVLink.h"
#import "TVProto.h"
#import "TVStore.h"
#import <CommonCrypto/CommonDigest.h>

/* polo.proto OuterMessage field numbers */
enum { F_PAIRING_REQUEST = 10, F_PAIRING_ACK = 11, F_OPTIONS = 20, F_CONFIGURATION = 30, F_CONFIGURATION_ACK = 31, F_SECRET = 40, F_SECRET_ACK = 41 };
enum { ENC_HEX = 3, SYMBOLS = 6, ROLE_INPUT = 1, STATUS_OK = 200 };

static NSData *outer(int field, NSData *inner) {
    NSMutableData *d = [NSMutableData data];
    TVPBVarint(d, 1, 2);                 /* protocol_version */
    TVPBVarint(d, 2, STATUS_OK);
    TVPBMessage(d, field, inner ?: [NSData data]);
    return d;
}

static NSData *encoding(void) {
    NSMutableData *e = [NSMutableData data];
    TVPBVarint(e, 1, ENC_HEX); TVPBVarint(e, 2, SYMBOLS);
    return e;
}

@interface TVPairing ()
@property (nonatomic, strong) TVLink *link;
@property (nonatomic) BOOL finished, codeStage;
@end

@implementation TVPairing

+ (NSData *)secretForCode:(NSString *)code clientModulus:(NSData *)cm clientExponent:(NSData *)ce serverModulus:(NSData *)sm serverExponent:(NSData *)se {
    if (code.length != 6) return nil;
    unsigned char bytes[3];
    for (int i = 0; i < 3; i++) {
        unsigned int v;
        NSScanner *sc = [NSScanner scannerWithString:[code substringWithRange:NSMakeRange(i * 2, 2)]];
        if (![sc scanHexInt:&v] || !sc.isAtEnd) return nil;
        bytes[i] = (unsigned char)v;
    }
    CC_SHA256_CTX c; CC_SHA256_Init(&c);
    CC_SHA256_Update(&c, cm.bytes, (CC_LONG)cm.length);
    CC_SHA256_Update(&c, ce.bytes, (CC_LONG)ce.length);
    CC_SHA256_Update(&c, sm.bytes, (CC_LONG)sm.length);
    CC_SHA256_Update(&c, se.bytes, (CC_LONG)se.length);
    CC_SHA256_Update(&c, bytes + 1, 2);
    unsigned char h[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(h, &c);
    if (h[0] != bytes[0]) return nil;
    return [NSData dataWithBytes:h length:sizeof h];
}

- (void)fail:(NSString *)why {
    if (self.finished) return;
    self.finished = YES;
    [self.link close]; self.link = nil;
    if (self.onFailed) self.onFailed(why);
}

- (void)startWithHost:(NSString *)host {
    TVStore *st = [TVStore shared];
    self.link = [[TVLink alloc] init];
    __weak TVPairing *me = self;
    self.link.onMessage = ^(NSData *raw) { [me handle:raw]; };
    self.link.onClose = ^(NSString *reason) { [me fail:reason ?: @"The TV closed the pairing connection."]; };
    int port = [TVStore remotePort:host] + 1;
    [self.link connectToHost:[TVStore hostOnly:host] port:port cert:st.certPem key:st.keyPem done:^(NSString *err) {
        if (err) { [me fail:err]; return; }
        NSMutableData *req = [NSMutableData data];
        TVPBString(req, 1, @"atvremote");
        TVPBString(req, 2, @"iPhone 5");
        [me.link send:outer(F_PAIRING_REQUEST, req)];
    }];
}

- (void)handle:(NSData *)raw {
    NSDictionary *m = TVPBParse(raw);
    if (!m) { [self fail:@"The TV sent something unreadable."]; return; }
    NSNumber *status = TVPBFirstNumber(m, 2);
    if (status && status.intValue != STATUS_OK) {
        [self fail:status.intValue == 402 ? @"The TV rejected the code." : [NSString stringWithFormat:@"The TV refused pairing (status %d).", status.intValue]];
        return;
    }
    if (TVPBFirstData(m, F_PAIRING_ACK)) {
        NSMutableData *o = [NSMutableData data];
        TVPBMessage(o, 1, encoding());
        TVPBVarint(o, 3, ROLE_INPUT);
        [self.link send:outer(F_OPTIONS, o)];
    } else if (TVPBFirstData(m, F_OPTIONS)) {
        NSMutableData *c = [NSMutableData data];
        TVPBMessage(c, 1, encoding());
        TVPBVarint(c, 2, ROLE_INPUT);
        [self.link send:outer(F_CONFIGURATION, c)];
    } else if (TVPBFirstData(m, F_CONFIGURATION_ACK)) {
        self.codeStage = YES;
        if (self.onNeedCode) self.onNeedCode();
    } else if (TVPBFirstData(m, F_SECRET_ACK)) {
        if (self.finished) return;
        self.finished = YES;
        [self.link close]; self.link = nil;
        if (self.onDone) self.onDone();
    }
}

- (void)submitCode:(NSString *)code {
    if (!self.codeStage || !self.link) return;
    code = [[code stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    NSData *cm, *ce, *sm, *se;
    if (!TVCertParts([TVStore shared].certPem, &cm, &ce) || ![self.link peerModulus:&sm exponent:&se]) { [self fail:@"Could not read the certificates."]; return; }
    NSData *secret = [TVPairing secretForCode:code clientModulus:cm clientExponent:ce serverModulus:sm serverExponent:se];
    if (!secret) { if (self.onBadCode) self.onBadCode(); return; }
    NSMutableData *s = [NSMutableData data];
    TVPBBytes(s, 1, secret);
    [self.link send:outer(F_SECRET, s)];
}

- (void)cancel {
    self.finished = YES;
    [self.link close]; self.link = nil;
    self.onNeedCode = nil; self.onBadCode = nil; self.onDone = nil; self.onFailed = nil;
}

@end
