#import "TVControls.h"
#import "TVRemote.h"
#import "TVStore.h"
#import "TVProto.h"

NSString *const TVNotConnected = @"TVNotConnected";

void TVPress(int keyCode) {
    if (![[TVRemote shared] sendKey:keyCode]) [[NSNotificationCenter defaultCenter] postNotificationName:TVNotConnected object:nil];
}

/* ---------- base ---------- */

@interface TVPad ()
@property (nonatomic) NSInteger pressedZone;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation TVPad

- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.pressedZone = -1; self.opaque = NO; self.contentMode = UIViewContentModeRedraw; }
    return self;
}

- (NSInteger)zoneAtPoint:(CGPoint)p { return CGRectContainsPoint(CGRectInset(self.bounds, -6, -6), p) ? 0 : -1; }
- (void)fireZone:(NSInteger)zone {}
- (BOOL)zoneRepeats:(NSInteger)zone { return self.repeats; }

- (void)stopRepeat { [self.timer invalidate]; self.timer = nil; }
- (void)startRepeating { self.timer = [NSTimer scheduledTimerWithTimeInterval:0.11 target:self selector:@selector(repeatFire) userInfo:nil repeats:YES]; }
- (void)repeatFire { if (self.pressedZone >= 0) [self fireZone:self.pressedZone]; }

- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    NSInteger z = [self zoneAtPoint:[t locationInView:self]];
    if (z < 0) return NO;
    self.pressedZone = z;
    TVHaptic();
    [self fireZone:z];
    [self setNeedsDisplay];
    [self stopRepeat];
    if ([self zoneRepeats:z]) self.timer = [NSTimer scheduledTimerWithTimeInterval:0.42 target:self selector:@selector(startRepeating) userInfo:nil repeats:NO];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    BOOL inside = CGRectContainsPoint(CGRectInset(self.bounds, -30, -30), [t locationInView:self]);
    if (!inside && self.pressedZone >= 0) { [self stopRepeat]; self.pressedZone = -1; [self setNeedsDisplay]; }
    return YES;
}

- (void)finish { [self stopRepeat]; self.pressedZone = -1; [self setNeedsDisplay]; }
- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { [self finish]; }
- (void)cancelTrackingWithEvent:(UIEvent *)e { [self finish]; }
- (void)removeFromSuperview { [self stopRepeat]; [super removeFromSuperview]; }

@end

/* ---------- plastic key ---------- */

@implementation TVKeyButton

+ (TVKeyButton *)keyWithGlyph:(TVGlyph)g label:(NSString *)label plastic:(TVPlastic)p key:(int)code {
    TVKeyButton *b = [[TVKeyButton alloc] initWithFrame:CGRectZero];
    b.glyph = g; b.label = label; b.plastic = p; b.keyCode = code;
    return b;
}

- (void)fireZone:(NSInteger)zone {
    if (self.keyCode) TVPress(self.keyCode);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect r = CGRectInset(self.bounds, 3, 3);
    BOOL down = self.pressedZone >= 0;
    CGFloat rad = self.radius > 0 ? self.radius : MIN(r.size.width, r.size.height) / 2;
    TVDrawKey(c, r, rad, self.plastic, down, self.lit);
    UIColor *ink = self.plastic == TVPlasticLight ? TVRGB(46, 46, 50) : self.plastic == TVPlasticAmber ? TVRGB(60, 30, 4) : TVRGB(232, 234, 238);
    CGRect inner = CGRectOffset(r, 0, down ? 1 : 0);
    BOOL both = self.glyph != TVGlyphNone && self.label.length;
    if (self.glyph != TVGlyphNone) {
        CGFloat g = MIN(inner.size.height - 12, 26);
        CGRect gr = both ? CGRectMake(CGRectGetMinX(inner) + 8, CGRectGetMidY(inner) - g / 2, g, g) : CGRectMake(CGRectGetMidX(inner) - g / 2, CGRectGetMidY(inner) - g / 2, g, g);
        TVDrawGlyph(c, self.glyph, gr, ink, self.plastic != TVPlasticLight);
    }
    if (self.label.length) {
        CGRect tr = both ? CGRectMake(CGRectGetMinX(inner) + 8 + 29, CGRectGetMidY(inner) - 8, inner.size.width - 36, 18) : CGRectMake(inner.origin.x + 2, CGRectGetMidY(inner) - 8, inner.size.width - 4, 18);
        UIFont *f = TVFont(@"HelveticaNeue-Bold", both ? 11 : 12);
        if (self.plastic == TVPlasticLight) TVDrawText(self.label, tr, f, ink, TVRGBA(255, 255, 255, 0.8), 1, both ? NSTextAlignmentLeft : NSTextAlignmentCenter);
        else TVDrawText(self.label, tr, f, ink, TVRGBA(0, 0, 0, 0.9), -1, both ? NSTextAlignmentLeft : NSTextAlignmentCenter);
    }
}

@end

/* ---------- d-pad ---------- */

@implementation TVDPad

- (CGFloat)R { return MIN(self.bounds.size.width, self.bounds.size.height) / 2 - 3; }
- (CGPoint)C { return CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds)); }

/* 0 up, 1 down, 2 left, 3 right, 4 OK */
- (NSInteger)zoneAtPoint:(CGPoint)p {
    CGFloat dx = p.x - self.C.x, dy = p.y - self.C.y, d = sqrt(dx * dx + dy * dy), R = self.R;
    if (d > R + 4) return -1;
    if (d < R * 0.36) return 4;
    if (fabs(dx) > fabs(dy)) return dx > 0 ? 3 : 2;
    return dy > 0 ? 1 : 0;
}

- (BOOL)zoneRepeats:(NSInteger)z { return z < 4; }

- (void)fireZone:(NSInteger)zone {
    static const int keys[5] = { TVKeyUp, TVKeyDown, TVKeyLeft, TVKeyRight, TVKeyCenter };
    TVPress(keys[zone]);
}

static void sector(CGContextRef c, CGPoint ctr, CGFloat ri, CGFloat ro, CGFloat a0, CGFloat a1) {
    CGContextBeginPath(c);
    CGContextAddArc(c, ctr.x, ctr.y, ro, a0, a1, 0);
    CGContextAddArc(c, ctr.x, ctr.y, ri, a1, a0, 1);
    CGContextClosePath(c);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGPoint ctr = self.C; CGFloat R = self.R;
    CGRect outer = CGRectMake(ctr.x - R, ctr.y - R, 2 * R, 2 * R);
    /* chrome ring with a drop shadow */
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 3), 5, TVRGBA(0, 0, 0, 0.9).CGColor);
    CGContextSetFillColorWithColor(c, TVRGB(20, 20, 20).CGColor);
    CGContextFillEllipseInRect(c, outer);
    CGContextRestoreGState(c);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, outer); CGContextClip(c);
    TVFillGradient(c, outer, TVRGB(250, 250, 252), TVRGB(70, 72, 78));
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    /* a darker band across the middle gives the chrome its reflection */
    CGFloat comps[16] = { 1, 1, 1, 0.0, 0.2, 0.2, 0.22, 0.55, 0.9, 0.9, 0.95, 0.65, 0.25, 0.25, 0.28, 0.0 };
    CGFloat locs[4] = { 0, 0.36, 0.62, 1 };
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, 4);
    CGContextDrawLinearGradient(c, g, CGPointMake(outer.origin.x, outer.origin.y), CGPointMake(CGRectGetMaxX(outer), CGRectGetMaxY(outer)), 0);
    CGGradientRelease(g);
    CGContextRestoreGState(c);
    CGContextSetStrokeColorWithColor(c, TVRGBA(0, 0, 0, 0.85).CGColor); CGContextSetLineWidth(c, 1);
    CGContextStrokeEllipseInRect(c, CGRectInset(outer, 0.5, 0.5));
    /* dish */
    CGFloat dishR = R - 9;
    CGRect dish = CGRectMake(ctr.x - dishR, ctr.y - dishR, 2 * dishR, 2 * dishR);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, dish); CGContextClip(c);
    CGFloat dc[8] = { 0.25, 0.26, 0.29, 1, 0.07, 0.07, 0.08, 1 };
    CGFloat dl[2] = { 0, 1 };
    g = CGGradientCreateWithColorComponents(cs, dc, dl, 2);
    CGContextDrawRadialGradient(c, g, CGPointMake(ctr.x, ctr.y - dishR * 0.25), dishR * 0.15, ctr, dishR, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(g);
    /* inner shadow along the top rim */
    TVFillGradient(c, CGRectMake(dish.origin.x, dish.origin.y, dish.size.width, dishR * 0.5), TVRGBA(0, 0, 0, 0.75), TVRGBA(0, 0, 0, 0));
    /* pressed sector */
    NSInteger z = self.pressedZone;
    if (z >= 0 && z < 4) {
        static const CGFloat centre[4] = { -M_PI / 2, M_PI / 2, M_PI, 0 };
        sector(c, ctr, R * 0.36, dishR + 1, centre[z] - M_PI / 4, centre[z] + M_PI / 4);
        CGContextSetFillColorWithColor(c, TVRGBA(255, 255, 255, 0.20).CGColor);
        CGContextFillPath(c);
    }
    CGContextRestoreGState(c);
    CGColorSpaceRelease(cs);
    CGContextSetStrokeColorWithColor(c, TVRGBA(255, 255, 255, 0.22).CGColor); CGContextSetLineWidth(c, 1);
    CGContextStrokeEllipseInRect(c, CGRectInset(dish, -0.5, -0.5));
    /* separators between the four sectors */
    for (int i = 0; i < 4; i++) {
        CGFloat a = M_PI / 4 + i * M_PI / 2;
        CGPoint p0 = CGPointMake(ctr.x + cos(a) * R * 0.38, ctr.y + sin(a) * R * 0.38), p1 = CGPointMake(ctr.x + cos(a) * dishR, ctr.y + sin(a) * dishR);
        CGContextSetStrokeColorWithColor(c, TVRGBA(0, 0, 0, 0.9).CGColor); CGContextSetLineWidth(c, 1.4);
        CGContextMoveToPoint(c, p0.x, p0.y); CGContextAddLineToPoint(c, p1.x, p1.y); CGContextStrokePath(c);
        CGContextSetStrokeColorWithColor(c, TVRGBA(255, 255, 255, 0.16).CGColor); CGContextSetLineWidth(c, 0.8);
        CGContextMoveToPoint(c, p0.x + 1, p0.y + 1); CGContextAddLineToPoint(c, p1.x + 1, p1.y + 1); CGContextStrokePath(c);
    }
    /* arrows */
    CGFloat ad = R * 0.69, as = R * 0.115;
    UIColor *ink = TVRGB(214, 216, 222);
    for (int i = 0; i < 4; i++) {
        CGFloat dx = i == 2 ? -1 : i == 3 ? 1 : 0, dy = i == 0 ? -1 : i == 1 ? 1 : 0;
        CGPoint tip = CGPointMake(ctr.x + dx * (ad + as), ctr.y + dy * (ad + as));
        CGPoint b1 = CGPointMake(ctr.x + dx * (ad - as) - dy * as * 1.5, ctr.y + dy * (ad - as) + dx * as * 1.5);
        CGPoint b2 = CGPointMake(ctr.x + dx * (ad - as) + dy * as * 1.5, ctr.y + dy * (ad - as) - dx * as * 1.5);
        CGContextSaveGState(c);
        CGContextSetShadowWithColor(c, CGSizeMake(0, -1), 0, TVRGBA(0, 0, 0, 0.9).CGColor);
        CGContextBeginPath(c); CGContextMoveToPoint(c, tip.x, tip.y); CGContextAddLineToPoint(c, b1.x, b1.y); CGContextAddLineToPoint(c, b2.x, b2.y); CGContextClosePath(c);
        CGContextSetFillColorWithColor(c, (z == i ? TVRGB(255, 255, 255) : ink).CGColor); CGContextFillPath(c);
        CGContextRestoreGState(c);
    }
    /* OK: chrome bezel and a glossy dark button */
    CGFloat okR = R * 0.36;
    CGRect okRing = CGRectMake(ctr.x - okR, ctr.y - okR, 2 * okR, 2 * okR);
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 2), 3, TVRGBA(0, 0, 0, 0.9).CGColor);
    CGContextSetFillColorWithColor(c, TVRGB(20, 20, 20).CGColor); CGContextFillEllipseInRect(c, okRing);
    CGContextRestoreGState(c);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, okRing); CGContextClip(c);
    TVFillGradient(c, okRing, TVRGB(240, 240, 244), TVRGB(80, 82, 88));
    CGContextRestoreGState(c);
    CGRect okKey = CGRectInset(okRing, 4, 4);
    TVDrawCircleKey(c, okKey, TVPlasticDark, z == 4, NO);
    TVDrawText(@"OK", CGRectOffset(CGRectMake(okKey.origin.x, CGRectGetMidY(okKey) - 11, okKey.size.width, 22), 0, z == 4 ? 1 : 0), TVFont(@"HelveticaNeue-Bold", 19), TVRGB(236, 238, 242), TVRGBA(0, 0, 0, 0.9), -1, NSTextAlignmentCenter);
}

@end

/* ---------- rocker ---------- */

@implementation TVRocker

- (CGRect)body { return CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height - (self.label.length ? 16 : 0)); }
- (NSInteger)zoneAtPoint:(CGPoint)p {
    CGRect b = CGRectInset([self body], -4, -4);
    if (!CGRectContainsPoint(b, p)) return -1;
    return p.y < CGRectGetMidY([self body]) ? 0 : 1;
}
- (BOOL)zoneRepeats:(NSInteger)z { return YES; }
- (void)fireZone:(NSInteger)zone { TVPress(zone == 0 ? self.topKey : self.bottomKey); }

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = CGRectInset([self body], 3, 3);
    CGFloat rad = MIN(b.size.width / 2, 24);
    TVDrawKey(c, b, rad, TVPlasticDark, NO, NO);
    NSInteger z = self.pressedZone;
    if (z >= 0) {
        CGContextSaveGState(c);
        TVRoundRectPath(c, b, rad); CGContextClip(c);
        CGRect half = z == 0 ? CGRectMake(b.origin.x, b.origin.y, b.size.width, b.size.height / 2) : CGRectMake(b.origin.x, CGRectGetMidY(b), b.size.width, b.size.height / 2);
        CGContextSetFillColorWithColor(c, TVRGBA(0, 0, 0, 0.35).CGColor); CGContextFillRect(c, half);
        CGContextRestoreGState(c);
    }
    /* groove between the halves */
    CGFloat my = CGRectGetMidY(b);
    CGContextSetStrokeColorWithColor(c, TVRGBA(0, 0, 0, 0.9).CGColor); CGContextSetLineWidth(c, 1.2);
    CGContextMoveToPoint(c, b.origin.x + 7, my); CGContextAddLineToPoint(c, CGRectGetMaxX(b) - 7, my); CGContextStrokePath(c);
    CGContextSetStrokeColorWithColor(c, TVRGBA(255, 255, 255, 0.18).CGColor); CGContextSetLineWidth(c, 0.8);
    CGContextMoveToPoint(c, b.origin.x + 7, my + 1); CGContextAddLineToPoint(c, CGRectGetMaxX(b) - 7, my + 1); CGContextStrokePath(c);
    CGFloat gs = 22;
    TVDrawGlyph(c, self.topGlyph, CGRectMake(CGRectGetMidX(b) - gs / 2, CGRectGetMinY(b) + (b.size.height / 2 - gs) / 2 + (z == 0 ? 1 : 0), gs, gs), z == 0 ? TVRGB(255, 255, 255) : TVRGB(228, 230, 234), YES);
    TVDrawGlyph(c, self.bottomGlyph, CGRectMake(CGRectGetMidX(b) - gs / 2, my + (b.size.height / 2 - gs) / 2 + (z == 1 ? 1 : 0), gs, gs), z == 1 ? TVRGB(255, 255, 255) : TVRGB(228, 230, 234), YES);
    if (self.label.length) TVDrawEngraved(self.label, CGRectMake(0, self.bounds.size.height - 15, self.bounds.size.width, 14), TVFont(@"HelveticaNeue-Bold", 10), NSTextAlignmentCenter);
}

@end

/* ---------- status plate ---------- */

@interface TVStatusPlate ()
@property (nonatomic) BOOL flash, down;
@end

@implementation TVStatusPlate

- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor clearColor]; self.opaque = NO; self.contentMode = UIViewContentModeRedraw;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:TVRemoteChanged object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notConnected) name:TVNotConnected object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)refresh { [self setNeedsDisplay]; }
- (void)notConnected {
    self.flash = YES; [self setNeedsDisplay];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ self.flash = NO; [self setNeedsDisplay]; });
}
- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { self.down = YES; [self setNeedsDisplay]; return YES; }
- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    BOOL hit = CGRectContainsPoint(self.bounds, [t locationInView:self]);
    self.down = NO; [self setNeedsDisplay];
    if (hit) [self sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)cancelTrackingWithEvent:(UIEvent *)e { self.down = NO; [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect r = CGRectInset(self.bounds, 3, 3);
    TVDrawPlate(c, r, 7);
    if (self.down) { CGContextSetFillColorWithColor(c, TVRGBA(0, 0, 0, 0.18).CGColor); TVRoundRectPath(c, r, 7); CGContextFillPath(c); }
    TVRemote *tv = [TVRemote shared];
    UIColor *led; BOOL on = NO;
    if (self.flash) { led = TVRGB(255, 40, 30); on = YES; }
    else if (tv.state == TVStateReady) { led = TVRGB(60, 235, 90); on = YES; }
    else if (tv.state == TVStateConnecting) { led = TVRGB(255, 176, 30); on = YES; }
    else led = TVRGB(120, 28, 24);
    CGPoint lp = CGPointMake(r.origin.x + 16, CGRectGetMidY(r));
    CGContextSaveGState(c);
    if (on) CGContextSetShadowWithColor(c, CGSizeZero, 8, led.CGColor);
    CGContextSetFillColorWithColor(c, led.CGColor);
    CGContextFillEllipseInRect(c, CGRectMake(lp.x - 5, lp.y - 5, 10, 10));
    CGContextRestoreGState(c);
    CGContextSetFillColorWithColor(c, TVRGBA(255, 255, 255, 0.55).CGColor);
    CGContextFillEllipseInRect(c, CGRectMake(lp.x - 2.8, lp.y - 3.8, 3.4, 2.6));
    CGContextSetStrokeColorWithColor(c, TVRGBA(0, 0, 0, 0.7).CGColor); CGContextSetLineWidth(c, 1);
    CGContextStrokeEllipseInRect(c, CGRectMake(lp.x - 5.5, lp.y - 5.5, 11, 11));
    NSString *name = nil, *sub = nil;
    NSDictionary *saved = tv.host ? [[TVStore shared] tvForHost:tv.host] : nil;
    if (tv.state == TVStateReady) { name = tv.deviceName.length ? tv.deviceName : [saved objectForKey:@"name"]; sub = tv.currentApp.length ? [self friendlyApp:tv.currentApp] : @"Connected"; }
    else if (tv.state == TVStateConnecting) { name = [saved objectForKey:@"name"]; sub = @"Connecting…"; }
    else if (tv.host) { name = [saved objectForKey:@"name"]; sub = tv.unpaired ? @"Not paired – tap to pair" : @"Offline – retrying"; }
    else { name = @"No TV selected"; sub = @"Tap to set up"; }
    CGRect tr = CGRectMake(r.origin.x + 30, r.origin.y + 3, r.size.width - 42, 17);
    TVDrawText(name ?: @"TV", tr, TVFont(@"HelveticaNeue-Bold", 14), TVRGB(30, 30, 34), TVRGBA(255, 255, 255, 0.7), 1, NSTextAlignmentLeft);
    TVDrawText(sub, CGRectMake(tr.origin.x, tr.origin.y + 16, tr.size.width, 13), TVFont(@"HelveticaNeue", 10.5), TVRGB(70, 70, 76), TVRGBA(255, 255, 255, 0.6), 1, NSTextAlignmentLeft);
    /* little chevron to say the plate opens something */
    CGContextSetStrokeColorWithColor(c, TVRGB(70, 70, 76).CGColor); CGContextSetLineWidth(c, 2); CGContextSetLineCap(c, kCGLineCapRound);
    CGFloat cx = CGRectGetMaxX(r) - 12, cy = CGRectGetMidY(r);
    CGContextMoveToPoint(c, cx - 3, cy - 4); CGContextAddLineToPoint(c, cx + 2, cy); CGContextAddLineToPoint(c, cx - 3, cy + 4); CGContextStrokePath(c);
}

- (NSString *)friendlyApp:(NSString *)pkg {
    static NSDictionary *names;
    if (!names) names = [NSDictionary dictionaryWithObjectsAndKeys:@"YouTube", @"com.google.android.youtube.tv", @"Netflix", @"com.netflix.ninja", @"Prime Video", @"com.amazon.amazonvideo.livingroom",
                         @"Disney+", @"com.disney.disneyplus", @"Kodi", @"org.xbmc.kodi", @"Spotify", @"com.spotify.tv.android", @"Home", @"com.google.android.tvlauncher", @"Google TV", @"com.google.android.apps.tv.launcherx",
                         @"Settings", @"com.android.tv.settings", @"Play Store", @"com.android.vending", nil];
    NSString *n = [names objectForKey:pkg];
    if (n) return n;
    NSRange r = [pkg rangeOfString:@"." options:NSBackwardsSearch];
    return r.location == NSNotFound ? pkg : [pkg substringFromIndex:r.location + 1];
}

@end

/* ---------- touchpad ---------- */

@interface TVTouchpad ()
@property (nonatomic) CGPoint start, last, accum;
@property (nonatomic) NSTimeInterval began;
@property (nonatomic) BOOL touching, moved, twoFingers;
@property (nonatomic) CGPoint glow;
@end

@implementation TVTouchpad

- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; self.multipleTouchEnabled = YES; self.contentMode = UIViewContentModeRedraw; }
    return self;
}

static const CGFloat STEP = 30;

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)e {
    NSSet *all = [e touchesForView:self];
    if (all.count >= 2) self.twoFingers = YES;
    if (!self.touching) {
        UITouch *t = [touches anyObject];
        self.touching = YES; self.moved = NO; self.twoFingers = all.count >= 2;
        self.start = self.last = self.glow = [t locationInView:self]; self.accum = CGPointZero; self.began = t.timestamp;
        [self setNeedsDisplay];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)e {
    if (!self.touching || [e touchesForView:self].count > 1) return;
    UITouch *t = [[e touchesForView:self] anyObject];
    CGPoint p = [t locationInView:self];
    self.accum = CGPointMake(self.accum.x + p.x - self.last.x, self.accum.y + p.y - self.last.y);
    self.last = self.glow = p;
    if (hypot(p.x - self.start.x, p.y - self.start.y) > 10) self.moved = YES;
    /* every STEP points along the dominant direction is one key press: a long swipe scrolls through a list */
    while (fabs(self.accum.x) >= STEP || fabs(self.accum.y) >= STEP) {
        int key;
        if (fabs(self.accum.x) >= fabs(self.accum.y)) { key = self.accum.x > 0 ? TVKeyRight : TVKeyLeft; self.accum = CGPointMake(self.accum.x + (self.accum.x > 0 ? -STEP : STEP), self.accum.y * 0.5); }
        else { key = self.accum.y > 0 ? TVKeyDown : TVKeyUp; self.accum = CGPointMake(self.accum.x * 0.5, self.accum.y + (self.accum.y > 0 ? -STEP : STEP)); }
        TVHaptic(); TVPress(key);
    }
    [self setNeedsDisplay];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)e {
    if (!self.touching) return;
    NSSet *remaining = [e touchesForView:self];
    BOOL last = YES;
    for (UITouch *t in remaining) if (t.phase != UITouchPhaseEnded && t.phase != UITouchPhaseCancelled) last = NO;
    if (!last) return;
    UITouch *t = [touches anyObject];
    BOOL quick = t.timestamp - self.began < 0.4;
    if (!self.moved && quick) { TVHaptic(); TVPress(self.twoFingers ? TVKeyBack : TVKeyCenter); }
    self.touching = NO; self.twoFingers = NO;
    [self setNeedsDisplay];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)e { self.touching = NO; self.twoFingers = NO; [self setNeedsDisplay]; }

- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect r = CGRectInset(self.bounds, 2, 2);
    TVDrawWell(c, r, 16);
    /* rubber dots */
    CGContextSaveGState(c);
    TVRoundRectPath(c, r, 16); CGContextClip(c);
    for (CGFloat y = r.origin.y + 9; y < CGRectGetMaxY(r); y += 12)
        for (CGFloat x = r.origin.x + 9 + (((int)((y - r.origin.y) / 12)) % 2 ? 6 : 0); x < CGRectGetMaxX(r); x += 12) {
            CGContextSetFillColorWithColor(c, TVRGBA(255, 255, 255, 0.05).CGColor);
            CGContextFillEllipseInRect(c, CGRectMake(x, y, 2.2, 2.2));
        }
    if (self.touching) {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[8] = { 1.0, 0.66, 0.2, 0.55, 1.0, 0.66, 0.2, 0.0 }; CGFloat locs[2] = { 0, 1 };
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
        CGContextDrawRadialGradient(c, g, self.glow, 0, self.glow, 54, 0);
        CGGradientRelease(g); CGColorSpaceRelease(cs);
    }
    CGContextRestoreGState(c);
    TVDrawText(@"TOUCH PAD", CGRectMake(r.origin.x, CGRectGetMidY(r) - 18, r.size.width, 16), TVFont(@"HelveticaNeue-Bold", 12), TVRGB(120, 122, 128), TVRGBA(0, 0, 0, 0.9), -1, NSTextAlignmentCenter);
    TVDrawText(@"swipe to move  ·  tap = OK  ·  two fingers = Back", CGRectMake(r.origin.x + 8, CGRectGetMidY(r) + 2, r.size.width - 16, 30), TVFont(@"HelveticaNeue", 10.5), TVRGB(98, 100, 106), TVRGBA(0, 0, 0, 0.9), -1, NSTextAlignmentCenter);
}

@end

/* ---------- page switch ---------- */

@interface TVPageSwitch ()
@property (nonatomic, copy) NSArray *titles, *glyphs;
@end

@implementation TVPageSwitch

- (id)initWithTitles:(NSArray *)titles glyphs:(NSArray *)glyphs {
    if ((self = [super initWithFrame:CGRectZero])) { self.titles = titles; self.glyphs = glyphs; self.backgroundColor = [UIColor clearColor]; self.opaque = NO; self.contentMode = UIViewContentModeRedraw; }
    return self;
}

- (void)setSelectedIndex:(NSInteger)i { _selectedIndex = i; [self setNeedsDisplay]; }

- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    NSInteger i = (NSInteger)floor([t locationInView:self].x / (self.bounds.size.width / self.titles.count));
    i = MAX(0, MIN(i, (NSInteger)self.titles.count - 1));
    if (i != _selectedIndex) { TVHaptic(); self.selectedIndex = i; [self sendActionsForControlEvents:UIControlEventValueChanged]; }
    return NO;
}

/* a full-width tab bar like the system one, in black glossy plastic: icons engraved, the selected tab lit amber in a recessed slot */
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = self.bounds;
    TVFillGradient(c, b, TVRGB(58, 59, 64), TVRGB(10, 10, 12));
    TVFillGradient(c, CGRectMake(0, 0, b.size.width, b.size.height * 0.5), TVRGBA(255, 255, 255, 0.10), TVRGBA(255, 255, 255, 0.0));
    CGContextSetFillColorWithColor(c, TVRGBA(0, 0, 0, 0.9).CGColor); CGContextFillRect(c, CGRectMake(0, 0, b.size.width, 1));
    CGContextSetFillColorWithColor(c, TVRGBA(255, 255, 255, 0.22).CGColor); CGContextFillRect(c, CGRectMake(0, 1, b.size.width, 1));
    CGFloat w = b.size.width / self.titles.count;
    for (NSUInteger i = 0; i < self.titles.count; i++) {
        CGRect seg = CGRectMake(i * w, 0, w, b.size.height);
        BOOL on = (NSInteger)i == self.selectedIndex;
        if (on) TVDrawWell(c, CGRectInset(seg, 5, 5), 9);
        UIColor *ink = on ? TVRGB(255, 176, 50) : TVRGB(150, 152, 160);
        CGContextSaveGState(c);
        if (on) CGContextSetShadowWithColor(c, CGSizeZero, 6, TVRGBA(255, 150, 20, 0.9).CGColor);
        TVDrawGlyph(c, (TVGlyph)[[self.glyphs objectAtIndex:i] integerValue], CGRectMake(CGRectGetMidX(seg) - 11, 7, 22, 22), ink, !on);
        CGContextRestoreGState(c);
        TVDrawText([self.titles objectAtIndex:i], CGRectMake(seg.origin.x, 32, seg.size.width, 12), TVFont(@"HelveticaNeue-Bold", 9.5), ink, TVRGBA(0, 0, 0, 0.9), -1, NSTextAlignmentCenter);
    }
}

@end
