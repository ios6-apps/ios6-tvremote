#import "TVLink.h"
#import "TVProto.h"
#import "TVTLS.h"

BOOL TVCertParts(NSString *certPem, NSData **mod, NSData **exp) {
    unsigned char m[600], e[16]; size_t ml = sizeof m, el = sizeof e;
    if (tv_cert_rsa(certPem.UTF8String, m, &ml, e, &el) != 0) return NO;
    *mod = [NSData dataWithBytes:m length:ml]; *exp = [NSData dataWithBytes:e length:el];
    return YES;
}

@interface TVLink () {
    TVConn *_conn;
    dispatch_queue_t _writeQ;
    BOOL _closing;
}
@end

@implementation TVLink

- (id)init {
    if ((self = [super init])) _writeQ = dispatch_queue_create("tvremote.write", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)open { return _conn != NULL && !_closing; }

- (void)connectToHost:(NSString *)host port:(int)port cert:(NSString *)cert key:(NSString *)key done:(void (^)(NSString *))done {
    NSString *h = [host copy], *c = [cert copy], *k = [key copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char err[200] = "";
        TVConn *conn = tv_tls_open(h.UTF8String, port, 8, c.UTF8String, k.UTF8String, err, sizeof err);
        NSString *error = conn ? nil : [NSString stringWithUTF8String:err];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!conn) { done(error); return; }
            if (_closing) { tv_tls_close(conn); done(@"closed"); return; }
            _conn = conn;
            done(nil);
            [self startReading:conn];
        });
    });
}

- (void)startReading:(TVConn *)conn {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableData *buf = [NSMutableData data];
        unsigned char chunk[2048];
        NSString *reason = nil;
        time_t lastData = time(NULL);
        for (;;) {
            int n = tv_tls_read(conn, chunk, sizeof chunk);
            if (n == -2) {      /* read timeout: the TV pings every few seconds, so a long silence means it is gone */
                if (time(NULL) - lastData > 20) { reason = @"The TV stopped answering."; break; }
                continue;
            }
            if (n == 0) break;
            if (n < 0) { reason = @"Connection lost."; break; }
            lastData = time(NULL);
            [buf appendBytes:chunk length:n];
            BOOL bad = NO;
            NSArray *msgs = TVPBTakeFrames(buf, &bad);
            if (msgs.count) dispatch_async(dispatch_get_main_queue(), ^{ for (NSData *m in msgs) if (!_closing && self.onMessage) self.onMessage(m); });
            if (bad) { reason = @"Garbled data from the TV."; break; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (_conn == conn) {
                _conn = NULL;
                BOOL wasClosing = _closing;
                dispatch_async(_writeQ, ^{ tv_tls_close(conn); });
                if (!wasClosing && self.onClose) self.onClose(reason);
            }
        });
    });
}

- (void)send:(NSData *)msg {
    TVConn *conn = _conn;
    if (!conn || _closing) return;
    NSData *frame = TVPBFrame(msg);
    dispatch_async(_writeQ, ^{ tv_tls_write(conn, frame.bytes, frame.length); });
}

/* only shuts the socket down; the reading thread notices, and its exit handler frees the connection after any queued writes */
- (void)close {
    _closing = YES;
    self.onMessage = nil; self.onClose = nil;
    if (_conn) tv_tls_cancel(_conn);
}

- (BOOL)peerModulus:(NSData **)mod exponent:(NSData **)exp {
    if (!_conn) return NO;
    unsigned char m[600], e[16]; size_t ml = sizeof m, el = sizeof e;
    if (tv_tls_peer_rsa(_conn, m, &ml, e, &el) != 0) return NO;
    *mod = [NSData dataWithBytes:m length:ml]; *exp = [NSData dataWithBytes:e length:el];
    return YES;
}

@end
