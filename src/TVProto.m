#import "TVProto.h"

static void put_varint(NSMutableData *d, unsigned long long v) {
    uint8_t b[10]; int n = 0;
    while (v >= 0x80) { b[n++] = (uint8_t)(v | 0x80); v >>= 7; }
    b[n++] = (uint8_t)v;
    [d appendBytes:b length:n];
}

void TVPBVarint(NSMutableData *d, int field, unsigned long long value) { put_varint(d, (unsigned long long)field << 3); put_varint(d, value); }
void TVPBBytes(NSMutableData *d, int field, NSData *value) { put_varint(d, ((unsigned long long)field << 3) | 2); put_varint(d, value.length); [d appendData:value]; }
void TVPBString(NSMutableData *d, int field, NSString *value) { TVPBBytes(d, field, [value dataUsingEncoding:NSUTF8StringEncoding]); }
void TVPBMessage(NSMutableData *d, int field, NSData *sub) { TVPBBytes(d, field, sub); }

/* reads a varint at *pos; NO when the data ends first or the number is longer than 10 bytes */
static BOOL get_varint(const uint8_t *p, NSUInteger len, NSUInteger *pos, unsigned long long *out) {
    unsigned long long v = 0; int shift = 0;
    while (*pos < len && shift < 70) {
        uint8_t b = p[(*pos)++];
        v |= (unsigned long long)(b & 0x7f) << shift;
        if (!(b & 0x80)) { *out = v; return YES; }
        shift += 7;
    }
    return NO;
}

NSDictionary *TVPBParse(NSData *msg) {
    const uint8_t *p = msg.bytes; NSUInteger len = msg.length, pos = 0;
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    while (pos < len) {
        unsigned long long tag;
        if (!get_varint(p, len, &pos, &tag)) return nil;
        NSNumber *field = [NSNumber numberWithUnsignedLongLong:tag >> 3];
        id value = nil;
        switch (tag & 7) {
            case 0: { unsigned long long v; if (!get_varint(p, len, &pos, &v)) return nil; value = [NSNumber numberWithUnsignedLongLong:v]; break; }
            case 1: if (pos + 8 > len) return nil; value = [NSData dataWithBytes:p + pos length:8]; pos += 8; break;
            case 5: if (pos + 4 > len) return nil; value = [NSData dataWithBytes:p + pos length:4]; pos += 4; break;
            case 2: { unsigned long long n; if (!get_varint(p, len, &pos, &n) || n > len - pos) return nil; value = [NSData dataWithBytes:p + pos length:(NSUInteger)n]; pos += (NSUInteger)n; break; }
            default: return nil;
        }
        NSMutableArray *list = [m objectForKey:field];
        if (!list) { list = [NSMutableArray array]; [m setObject:list forKey:field]; }
        [list addObject:value];
    }
    return m;
}

NSData *TVPBFirstData(NSDictionary *m, int field) { id v = [[m objectForKey:[NSNumber numberWithInt:field]] firstObject]; return [v isKindOfClass:[NSData class]] ? v : nil; }
NSNumber *TVPBFirstNumber(NSDictionary *m, int field) { id v = [[m objectForKey:[NSNumber numberWithInt:field]] firstObject]; return [v isKindOfClass:[NSNumber class]] ? v : nil; }
NSString *TVPBFirstString(NSDictionary *m, int field) { NSData *d = TVPBFirstData(m, field); return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil; }

NSData *TVPBFrame(NSData *msg) {
    NSMutableData *d = [NSMutableData data];
    put_varint(d, msg.length);
    [d appendData:msg];
    return d;
}

NSArray *TVPBTakeFrames(NSMutableData *buf, BOOL *bad) {
    NSMutableArray *out = [NSMutableArray array];
    for (;;) {
        const uint8_t *p = buf.bytes; NSUInteger pos = 0; unsigned long long n;
        if (!get_varint(p, buf.length, &pos, &n)) break;
        if (n > (1 << 20)) { if (bad) *bad = YES; break; }
        if (buf.length - pos < n) break;
        [out addObject:[NSData dataWithBytes:p + pos length:(NSUInteger)n]];
        [buf replaceBytesInRange:NSMakeRange(0, pos + (NSUInteger)n) withBytes:NULL length:0];
    }
    return out;
}
