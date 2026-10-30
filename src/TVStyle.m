#import "TVStyle.h"
#import <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>

const CGFloat TVFaceMargin = 12;

UIColor *TVRGB(int r, int g, int b) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:1]; }
UIColor *TVRGBA(int r, int g, int b, CGFloat a) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a]; }
UIFont *TVFont(NSString *name, CGFloat size) { return [UIFont fontWithName:name size:size] ?: [UIFont boldSystemFontOfSize:size]; }

void TVRoundRectPath(CGContextRef c, CGRect r, CGFloat rad) {
    rad = MIN(rad, MIN(r.size.width, r.size.height) / 2);
    CGContextBeginPath(c);
    CGContextMoveToPoint(c, CGRectGetMinX(r) + rad, CGRectGetMinY(r));
    CGContextAddArcToPoint(c, CGRectGetMaxX(r), CGRectGetMinY(r), CGRectGetMaxX(r), CGRectGetMaxY(r), rad);
    CGContextAddArcToPoint(c, CGRectGetMaxX(r), CGRectGetMaxY(r), CGRectGetMinX(r), CGRectGetMaxY(r), rad);
    CGContextAddArcToPoint(c, CGRectGetMinX(r), CGRectGetMaxY(r), CGRectGetMinX(r), CGRectGetMinY(r), rad);
    CGContextAddArcToPoint(c, CGRectGetMinX(r), CGRectGetMinY(r), CGRectGetMaxX(r), CGRectGetMinY(r), rad);
    CGContextClosePath(c);
}

/* stops: (location, r, g, b, a) * n, top to bottom */
static void gradient(CGContextRef c, CGRect r, const CGFloat *stops, int n) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[8 * 4], locs[8];
    for (int i = 0; i < n; i++) { locs[i] = stops[i * 5]; for (int k = 0; k < 4; k++) comps[i * 4 + k] = stops[i * 5 + 1 + k]; }
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, n);
    CGContextSaveGState(c);
    CGContextClipToRect(c, r);
    CGContextDrawLinearGradient(c, g, CGPointMake(CGRectGetMidX(r), CGRectGetMinY(r)), CGPointMake(CGRectGetMidX(r), CGRectGetMaxY(r)), 0);
    CGContextRestoreGState(c);
    CGGradientRelease(g); CGColorSpaceRelease(cs);
}

static void rgba(UIColor *col, CGFloat *out) { [col getRed:out green:out + 1 blue:out + 2 alpha:out + 3]; }

void TVFillGradient(CGContextRef c, CGRect r, UIColor *top, UIColor *bottom) {
    CGFloat a[4], b[4]; rgba(top, a); rgba(bottom, b);
    CGFloat st[10] = { 0, a[0], a[1], a[2], a[3], 1, b[0], b[1], b[2], b[3] };
    gradient(c, r, st, 2);
}

/* ---------- wood ---------- */

static unsigned rngState;
static double rnd(void) { rngState = rngState * 1664525u + 1013904223u; return (rngState >> 8) / 16777216.0; }

UIImage *TVWoodImage(CGSize size) {
    static UIImage *cache; static CGSize cachedSize;
    if (cache && CGSizeEqualToSize(cachedSize, size)) return cache;
    rngState = 7;
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    const CGFloat base[] = { 0, 0.40, 0.23, 0.12, 1, 0.5, 0.30, 0.16, 1, 1, 0.34, 0.19, 0.10, 1 };
    gradient(c, CGRectMake(0, 0, size.width, size.height), (const CGFloat[]){ 0, 0.40, 0.22, 0.115, 1, 0.5, 0.47, 0.26, 0.14, 1, 1, 0.33, 0.18, 0.095, 1 }, 3);
    (void)base;
    /* broad soft bands: the heartwood / sapwood colour changes across the plank */
    for (int i = 0; i < 22; i++) {
        CGFloat x = rnd() * size.width, w = 10 + rnd() * 46;
        CGFloat al = 0.05 + rnd() * 0.08;
        UIColor *col = rnd() < 0.5 ? TVRGBA(30, 14, 5, al) : TVRGBA(170, 104, 56, al * 0.7);
        CGContextSetFillColorWithColor(c, col.CGColor);
        CGContextFillRect(c, CGRectMake(x - w / 2, 0, w, size.height));
    }
    /* grain: long thin wavy lines */
    CGContextSetLineCap(c, kCGLineCapRound);
    for (int i = 0; i < 420; i++) {
        CGFloat x0 = rnd() * size.width, amp = 1 + rnd() * 5, freq = 0.004 + rnd() * 0.012, phase = rnd() * 6.28, drift = (rnd() - 0.5) * 14;
        CGFloat w = 0.4 + rnd() * 1.6;
        BOOL dark = rnd() < 0.62;
        CGFloat al = dark ? 0.06 + rnd() * 0.20 : 0.04 + rnd() * 0.12;
        CGContextSetStrokeColorWithColor(c, (dark ? TVRGBA(28, 13, 5, al) : TVRGBA(190, 120, 66, al)).CGColor);
        CGContextSetLineWidth(c, w);
        CGFloat y0 = (rnd() < 0.5) ? -10 : rnd() * size.height * 0.6, y1 = y0 + 120 + rnd() * size.height;
        CGContextBeginPath(c);
        for (CGFloat y = y0; y <= y1 && y < size.height + 10; y += 7) {
            CGFloat t = (y - y0) / MAX(1, y1 - y0);
            CGFloat x = x0 + amp * sin(y * freq + phase) + drift * t + amp * 0.4 * sin(y * freq * 3.1 + phase * 2);
            if (y == y0) CGContextMoveToPoint(c, x, y); else CGContextAddLineToPoint(c, x, y);
        }
        CGContextStrokePath(c);
    }
    /* a few pores: short dark dashes */
    for (int i = 0; i < 700; i++) {
        CGFloat x = rnd() * size.width, y = rnd() * size.height, l = 2 + rnd() * 9;
        CGContextSetStrokeColorWithColor(c, TVRGBA(20, 9, 3, 0.12 + rnd() * 0.18).CGColor);
        CGContextSetLineWidth(c, 0.6);
        CGContextMoveToPoint(c, x, y); CGContextAddLineToPoint(c, x + (rnd() - 0.5) * 1.2, y + l); CGContextStrokePath(c);
    }
    /* varnish: a diagonal sheen and a darkened edge */
    CGContextSaveGState(c);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[8] = { 1, 0.85, 0.65, 0.16, 1, 0.85, 0.65, 0.0 };
    CGFloat locs[2] = { 0, 1 };
    CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, 0), CGPointMake(size.width * 0.9, size.height * 0.35), 0);
    CGGradientRelease(g);
    CGFloat vc[8] = { 0, 0, 0, 0, 0, 0, 0, 0.55 };
    g = CGGradientCreateWithColorComponents(cs, vc, locs, 2);
    CGContextDrawRadialGradient(c, g, CGPointMake(size.width / 2, size.height / 2), size.height * 0.45, CGPointMake(size.width / 2, size.height / 2), size.height * 0.85, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(g); CGColorSpaceRelease(cs);
    CGContextRestoreGState(c);
    cache = UIGraphicsGetImageFromCurrentImageContext();
    cachedSize = size;
    UIGraphicsEndImageContext();
    return cache;
}

/* ---------- faceplate ---------- */

static void screw(CGContextRef c, CGPoint p, CGFloat rad, CGFloat angle) {
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 1.5, TVRGBA(0, 0, 0, 0.9).CGColor);
    CGContextSetFillColorWithColor(c, TVRGB(20, 20, 20).CGColor);
    CGContextFillEllipseInRect(c, CGRectMake(p.x - rad - 1, p.y - rad - 1, 2 * rad + 2, 2 * rad + 2));
    CGContextRestoreGState(c);
    CGContextSaveGState(c);
    CGContextAddEllipseInRect(c, CGRectMake(p.x - rad, p.y - rad, 2 * rad, 2 * rad));
    CGContextClip(c);
    gradient(c, CGRectMake(p.x - rad, p.y - rad, 2 * rad, 2 * rad), (const CGFloat[]){ 0, 0.95, 0.80, 0.50, 1, 0.45, 0.78, 0.55, 0.28, 1, 1, 0.55, 0.40, 0.18, 1 }, 3);
    CGContextRestoreGState(c);
    CGContextSetStrokeColorWithColor(c, TVRGBA(255, 235, 170, 0.6).CGColor);
    CGContextSetLineWidth(c, 0.6);
    CGContextStrokeEllipseInRect(c, CGRectMake(p.x - rad + 0.3, p.y - rad + 0.3, 2 * rad - 0.6, 2 * rad - 0.6));
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, p.x, p.y); CGContextRotateCTM(c, angle);
    CGContextSetStrokeColorWithColor(c, TVRGBA(40, 24, 8, 0.95).CGColor);
    CGContextSetLineWidth(c, 1.6);
    CGContextMoveToPoint(c, -rad * 0.72, 0); CGContextAddLineToPoint(c, rad * 0.72, 0); CGContextStrokePath(c);
    CGContextSetStrokeColorWithColor(c, TVRGBA(255, 230, 160, 0.5).CGColor);
    CGContextSetLineWidth(c, 0.6);
    CGContextMoveToPoint(c, -rad * 0.72, 1.1); CGContextAddLineToPoint(c, rad * 0.72, 1.1); CGContextStrokePath(c);
    CGContextRestoreGState(c);
}

UIImage *TVFaceplateImage(CGSize size) {
    static UIImage *cache; static CGSize cachedSize;
    if (cache && CGSizeEqualToSize(cachedSize, size)) return cache;
    rngState = 99;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect body = CGRectInset(CGRectMake(0, 0, size.width, size.height), TVFaceMargin, TVFaceMargin);
    CGFloat rad = 26;
    /* shadow onto the wood */
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 5), 9, TVRGBA(0, 0, 0, 0.85).CGColor);
    TVRoundRectPath(c, body, rad);
    CGContextSetFillColorWithColor(c, TVRGB(10, 10, 11).CGColor);
    CGContextFillPath(c);
    CGContextRestoreGState(c);
    /* plastic */
    CGContextSaveGState(c);
    TVRoundRectPath(c, body, rad); CGContextClip(c);
    gradient(c, body, (const CGFloat[]){ 0, 0.20, 0.21, 0.23, 1, 0.45, 0.115, 0.12, 0.13, 1, 1, 0.07, 0.07, 0.08, 1 }, 3);
    /* fine texture */
    for (int i = 0; i < 2600; i++) {
        CGFloat x = body.origin.x + rnd() * body.size.width, y = body.origin.y + rnd() * body.size.height;
        CGContextSetFillColorWithColor(c, (rnd() < 0.5 ? TVRGBA(255, 255, 255, 0.035) : TVRGBA(0, 0, 0, 0.10)).CGColor);
        CGContextFillRect(c, CGRectMake(x, y, 1, 1));
    }
    /* soft sheen: a big radial glow centred above the top edge */
    {
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[8] = { 1, 1, 1, 0.16, 1, 1, 1, 0.0 }; CGFloat locs[2] = { 0, 1 };
        CGGradientRef g = CGGradientCreateWithColorComponents(cs, comps, locs, 2);
        CGContextDrawRadialGradient(c, g, CGPointMake(CGRectGetMidX(body) - body.size.width * 0.15, body.origin.y - 60), 0, CGPointMake(CGRectGetMidX(body) - body.size.width * 0.15, body.origin.y - 60), body.size.height * 0.62, 0);
        CGGradientRelease(g); CGColorSpaceRelease(cs);
    }
    CGContextRestoreGState(c);
    /* bevel: light rim on top-left, dark on bottom */
    CGContextSaveGState(c);
    TVRoundRectPath(c, CGRectInset(body, 0.75, 0.75), rad - 0.75);
    CGContextReplacePathWithStrokedPath(c); CGContextClip(c);
    gradient(c, body, (const CGFloat[]){ 0, 1, 1, 1, 0.42, 0.5, 0.5, 0.5, 0.5, 0.05, 1, 0, 0, 0, 0.7 }, 3);
    CGContextRestoreGState(c);
    CGFloat in = 17;
    screw(c, CGPointMake(CGRectGetMinX(body) + in, CGRectGetMinY(body) + in), 4.2, 0.5);
    screw(c, CGPointMake(CGRectGetMaxX(body) - in, CGRectGetMinY(body) + in), 4.2, 2.2);
    screw(c, CGPointMake(CGRectGetMinX(body) + in, CGRectGetMaxY(body) - in), 4.2, 1.1);
    screw(c, CGPointMake(CGRectGetMaxX(body) - in, CGRectGetMaxY(body) - in), 4.2, 2.9);
    cache = UIGraphicsGetImageFromCurrentImageContext();
    cachedSize = size;
    UIGraphicsEndImageContext();
    return cache;
}

/* ---------- keys, plates, wells ---------- */

static void kindColors(TVPlastic k, BOOL pressed, BOOL lit, CGFloat out[10]) {
    /* top, mid, bottom as (r,g,b) triples in 0..1 plus gloss strength */
    static const CGFloat dark[9] = { 0.34, 0.35, 0.38, 0.19, 0.20, 0.22, 0.09, 0.09, 0.10 };
    static const CGFloat light[9] = { 0.93, 0.93, 0.91, 0.78, 0.78, 0.77, 0.56, 0.56, 0.56 };
    static const CGFloat red[9] = { 1.00, 0.36, 0.28, 0.82, 0.10, 0.07, 0.45, 0.02, 0.02 };
    static const CGFloat amber[9] = { 1.00, 0.80, 0.40, 0.95, 0.55, 0.10, 0.60, 0.25, 0.02 };
    const CGFloat *src = k == TVPlasticLight ? light : k == TVPlasticRed ? red : k == TVPlasticAmber ? amber : dark;
    for (int i = 0; i < 9; i++) {
        CGFloat v = src[i];
        if (pressed) v *= 0.72;
        if (lit && k == TVPlasticDark) v = MIN(1, v * 1.0 + (i % 3 == 0 ? 0.20 : i % 3 == 1 ? 0.10 : -0.03));
        out[i] = v;
    }
    out[9] = k == TVPlasticLight ? 0.55 : 0.28;
}

void TVDrawKey(CGContextRef c, CGRect r, CGFloat radius, TVPlastic kind, BOOL pressed, BOOL lit) {
    CGFloat k[10]; kindColors(kind, pressed, lit, k);
    if (!pressed) {
        CGContextSaveGState(c);
        CGContextSetShadowWithColor(c, CGSizeMake(0, 2), 3, TVRGBA(0, 0, 0, 0.85).CGColor);
        TVRoundRectPath(c, r, radius);
        CGContextSetFillColorWithColor(c, TVRGB(8, 8, 9).CGColor);
        CGContextFillPath(c);
        CGContextRestoreGState(c);
    }
    CGRect body = pressed ? CGRectOffset(r, 0, 1) : r;
    CGContextSaveGState(c);
    TVRoundRectPath(c, body, radius); CGContextClip(c);
    gradient(c, body, (const CGFloat[]){ 0, k[0], k[1], k[2], 1, 0.5, k[3], k[4], k[5], 1, 1, k[6], k[7], k[8], 1 }, 3);
    /* specular gloss on the upper half */
    CGRect gl = CGRectMake(body.origin.x + 1, body.origin.y + 1, body.size.width - 2, body.size.height * 0.48);
    CGContextSaveGState(c);
    TVRoundRectPath(c, gl, radius - 1); CGContextClip(c);
    gradient(c, gl, (const CGFloat[]){ 0, 1, 1, 1, k[9] * (pressed ? 0.5 : 1), 1, 1, 1, 1, 0.02 }, 2);
    CGContextRestoreGState(c);
    CGContextRestoreGState(c);
    /* rim */
    CGContextSaveGState(c);
    TVRoundRectPath(c, CGRectInset(body, 0.5, 0.5), radius - 0.5);
    CGContextReplacePathWithStrokedPath(c); CGContextClip(c);
    gradient(c, body, (const CGFloat[]){ 0, 1, 1, 1, 0.55, 0.45, 0, 0, 0, 0.45, 1, 0, 0, 0, 0.85 }, 3);
    CGContextRestoreGState(c);
    TVRoundRectPath(c, CGRectInset(body, -0.5, -0.5), radius + 0.5);
    CGContextSetStrokeColorWithColor(c, TVRGBA(0, 0, 0, 0.9).CGColor);
    CGContextSetLineWidth(c, 1);
    CGContextStrokePath(c);
}

void TVDrawCircleKey(CGContextRef c, CGRect r, TVPlastic kind, BOOL pressed, BOOL lit) { TVDrawKey(c, r, MIN(r.size.width, r.size.height) / 2, kind, pressed, lit); }

void TVDrawPlate(CGContextRef c, CGRect r, CGFloat radius) {
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 1.5), 2.5, TVRGBA(0, 0, 0, 0.8).CGColor);
    TVRoundRectPath(c, r, radius); CGContextSetFillColorWithColor(c, TVRGB(60, 60, 60).CGColor); CGContextFillPath(c);
    CGContextRestoreGState(c);
    CGContextSaveGState(c);
    TVRoundRectPath(c, r, radius); CGContextClip(c);
    gradient(c, r, (const CGFloat[]){ 0, 0.86, 0.86, 0.87, 1, 0.5, 0.62, 0.62, 0.64, 1, 0.52, 0.55, 0.55, 0.57, 1, 1, 0.72, 0.72, 0.74, 1 }, 4);
    /* brushing */
    unsigned save = rngState; rngState = 5;
    for (int i = 0; i < (int)(r.size.width * r.size.height / 40); i++) {
        CGFloat x = r.origin.x + rnd() * r.size.width, y = r.origin.y + rnd() * r.size.height, l = 6 + rnd() * 26;
        CGContextSetStrokeColorWithColor(c, (rnd() < 0.5 ? TVRGBA(255, 255, 255, 0.16) : TVRGBA(0, 0, 0, 0.08)).CGColor);
        CGContextSetLineWidth(c, 0.5);
        CGContextMoveToPoint(c, x, y); CGContextAddLineToPoint(c, x + l, y); CGContextStrokePath(c);
    }
    rngState = save;
    CGContextRestoreGState(c);
    TVRoundRectPath(c, CGRectInset(r, 0.5, 0.5), radius);
    CGContextSetStrokeColorWithColor(c, TVRGBA(0, 0, 0, 0.7).CGColor); CGContextSetLineWidth(c, 1); CGContextStrokePath(c);
    TVRoundRectPath(c, CGRectInset(r, 1.5, 1.5), radius - 1);
    CGContextSetStrokeColorWithColor(c, TVRGBA(255, 255, 255, 0.55).CGColor); CGContextSetLineWidth(c, 0.8); CGContextStrokePath(c);
}

void TVDrawWell(CGContextRef c, CGRect r, CGFloat radius) {
    CGContextSaveGState(c);
    TVRoundRectPath(c, r, radius); CGContextClip(c);
    gradient(c, r, (const CGFloat[]){ 0, 0.0, 0.0, 0.0, 1, 0.5, 0.05, 0.05, 0.06, 1, 1, 0.13, 0.13, 0.14, 1 }, 3);
    /* inner shadow along the top edge */
    gradient(c, CGRectMake(r.origin.x, r.origin.y, r.size.width, 6), (const CGFloat[]){ 0, 0, 0, 0, 0.8, 1, 0, 0, 0, 0 }, 2);
    CGContextRestoreGState(c);
    TVRoundRectPath(c, CGRectInset(r, -0.5, -0.5), radius + 0.5);
    CGContextSetStrokeColorWithColor(c, TVRGBA(255, 255, 255, 0.14).CGColor); CGContextSetLineWidth(c, 1); CGContextStrokePath(c);
    TVRoundRectPath(c, CGRectInset(r, 0.5, 0.5), radius);
    CGContextSetStrokeColorWithColor(c, TVRGBA(0, 0, 0, 0.9).CGColor); CGContextStrokePath(c);
}

/* ---------- text ---------- */

void TVDrawText(NSString *s, CGRect r, UIFont *font, UIColor *color, UIColor *shadow, CGFloat dy, NSTextAlignment align) {
    if (!s.length) return;
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSaveGState(c);
    if (shadow) CGContextSetShadowWithColor(c, CGSizeMake(0, dy), 0, shadow.CGColor);
    [color set];
    [s drawInRect:r withFont:font lineBreakMode:NSLineBreakByTruncatingTail alignment:align];
    CGContextRestoreGState(c);
}

void TVDrawEngraved(NSString *s, CGRect r, UIFont *font, NSTextAlignment align) {
    TVDrawText(s, r, font, TVRGB(176, 178, 184), TVRGBA(0, 0, 0, 0.9), -1, align);
}

/* ---------- glyphs ---------- */

static void fillAndShadow(CGContextRef c, UIColor *color, BOOL engraved) {
    if (engraved) {
        CGContextSaveGState(c);
        CGContextSetShadowWithColor(c, CGSizeMake(0, -1), 0, TVRGBA(0, 0, 0, 0.85).CGColor);
        CGContextSetFillColorWithColor(c, color.CGColor);
        CGContextFillPath(c);
        CGContextRestoreGState(c);
    } else { CGContextSetFillColorWithColor(c, color.CGColor); CGContextFillPath(c); }
}

static void tri(CGContextRef c, CGPoint a, CGPoint b, CGPoint d) { CGContextMoveToPoint(c, a.x, a.y); CGContextAddLineToPoint(c, b.x, b.y); CGContextAddLineToPoint(c, d.x, d.y); CGContextClosePath(c); }

void TVDrawGlyph(CGContextRef c, TVGlyph g, CGRect r, UIColor *color, BOOL engraved) {
    CGFloat s = MIN(r.size.width, r.size.height), cx = CGRectGetMidX(r), cy = CGRectGetMidY(r), u = s / 24.0;
    CGContextSaveGState(c);
    CGContextTranslateCTM(c, cx, cy);
    CGContextScaleCTM(c, u, u);       /* drawing space: 24 x 24 units centred on the origin */
    UIColor *stroke = color;
    CGContextSetStrokeColorWithColor(c, stroke.CGColor);
    CGContextSetLineCap(c, kCGLineCapRound); CGContextSetLineJoin(c, kCGLineJoinRound);
    CGContextSetLineWidth(c, 2.6);
    switch (g) {
        case TVGlyphPower: {
            CGContextAddArc(c, 0, 1, 8, -M_PI / 2 + 0.62, -M_PI / 2 - 0.62 + 2 * M_PI, 0);
            CGContextStrokePath(c);
            CGContextMoveToPoint(c, 0, -10); CGContextAddLineToPoint(c, 0, 0); CGContextStrokePath(c);
            break; }
        case TVGlyphBack: {
            CGContextMoveToPoint(c, -4, -7); CGContextAddLineToPoint(c, -10, -1); CGContextAddLineToPoint(c, -4, 5); CGContextStrokePath(c);
            CGContextMoveToPoint(c, -9, -1); CGContextAddLineToPoint(c, 3, -1); CGContextAddCurveToPoint(c, 9, -1, 10, 4, 7, 8); CGContextStrokePath(c);
            break; }
        case TVGlyphHome: {
            CGContextBeginPath(c);
            CGContextMoveToPoint(c, 0, -10); CGContextAddLineToPoint(c, 10, -1); CGContextAddLineToPoint(c, 7.5, -1); CGContextAddLineToPoint(c, 7.5, 9);
            CGContextAddLineToPoint(c, 2.5, 9); CGContextAddLineToPoint(c, 2.5, 3); CGContextAddLineToPoint(c, -2.5, 3); CGContextAddLineToPoint(c, -2.5, 9);
            CGContextAddLineToPoint(c, -7.5, 9); CGContextAddLineToPoint(c, -7.5, -1); CGContextAddLineToPoint(c, -10, -1); CGContextClosePath(c);
            fillAndShadow(c, color, engraved);
            break; }
        case TVGlyphMenu: {
            for (int i = -1; i <= 1; i++) { CGContextMoveToPoint(c, -8, i * 6); CGContextAddLineToPoint(c, 8, i * 6); CGContextStrokePath(c); }
            break; }
        case TVGlyphInfo: {
            CGContextAddEllipseInRect(c, CGRectMake(-10, -10, 20, 20)); CGContextStrokePath(c);
            CGContextMoveToPoint(c, 0, -1); CGContextAddLineToPoint(c, 0, 5); CGContextStrokePath(c);
            CGContextAddEllipseInRect(c, CGRectMake(-1.4, -6.4, 2.8, 2.8)); fillAndShadow(c, color, NO);
            break; }
        case TVGlyphInput: {
            CGContextSetLineWidth(c, 2.2);
            CGContextMoveToPoint(c, 3, -8); CGContextAddLineToPoint(c, -9, -8); CGContextAddLineToPoint(c, -9, 8); CGContextAddLineToPoint(c, 3, 8); CGContextStrokePath(c);
            CGContextMoveToPoint(c, -3, 0); CGContextAddLineToPoint(c, 9, 0); CGContextStrokePath(c);
            CGContextMoveToPoint(c, 5, -4); CGContextAddLineToPoint(c, 9, 0); CGContextAddLineToPoint(c, 5, 4); CGContextStrokePath(c);
            break; }
        case TVGlyphSettings: {
            CGContextSetLineWidth(c, 2.2);
            CGContextAddEllipseInRect(c, CGRectMake(-3.6, -3.6, 7.2, 7.2)); CGContextStrokePath(c);
            for (int i = 0; i < 8; i++) {
                CGFloat a = i * M_PI / 4;
                CGContextMoveToPoint(c, cos(a) * 6.8, sin(a) * 6.8); CGContextAddLineToPoint(c, cos(a) * 10, sin(a) * 10);
            }
            CGContextSetLineWidth(c, 3.4); CGContextStrokePath(c);
            CGContextSetLineWidth(c, 2.2);
            CGContextAddEllipseInRect(c, CGRectMake(-7, -7, 14, 14)); CGContextStrokePath(c);
            break; }
        case TVGlyphGuide: {
            CGContextSetLineWidth(c, 2);
            for (int row = 0; row < 3; row++) for (int col = 0; col < 3; col++) CGContextAddRect(c, CGRectMake(-9.5 + col * 6.7, -9.5 + row * 6.7, 5.4, 5.4));
            fillAndShadow(c, color, NO);
            break; }
        case TVGlyphPlus: { CGContextSetLineWidth(c, 3.4); CGContextMoveToPoint(c, -8, 0); CGContextAddLineToPoint(c, 8, 0); CGContextMoveToPoint(c, 0, -8); CGContextAddLineToPoint(c, 0, 8); CGContextStrokePath(c); break; }
        case TVGlyphMinus: { CGContextSetLineWidth(c, 3.4); CGContextMoveToPoint(c, -8, 0); CGContextAddLineToPoint(c, 8, 0); CGContextStrokePath(c); break; }
        case TVGlyphMute: {
            CGContextBeginPath(c);
            CGContextMoveToPoint(c, -10, -3.5); CGContextAddLineToPoint(c, -5, -3.5); CGContextAddLineToPoint(c, 1, -9); CGContextAddLineToPoint(c, 1, 9);
            CGContextAddLineToPoint(c, -5, 3.5); CGContextAddLineToPoint(c, -10, 3.5); CGContextClosePath(c);
            fillAndShadow(c, color, engraved);
            CGContextSetLineWidth(c, 2.4);
            CGContextMoveToPoint(c, 4.5, -3.5); CGContextAddLineToPoint(c, 10.5, 3.5); CGContextMoveToPoint(c, 10.5, -3.5); CGContextAddLineToPoint(c, 4.5, 3.5); CGContextStrokePath(c);
            break; }
        case TVGlyphChevronUp: { CGContextSetLineWidth(c, 3.6); CGContextMoveToPoint(c, -8, 4); CGContextAddLineToPoint(c, 0, -4); CGContextAddLineToPoint(c, 8, 4); CGContextStrokePath(c); break; }
        case TVGlyphChevronDown: { CGContextSetLineWidth(c, 3.6); CGContextMoveToPoint(c, -8, -4); CGContextAddLineToPoint(c, 0, 4); CGContextAddLineToPoint(c, 8, -4); CGContextStrokePath(c); break; }
        case TVGlyphPlayPause: {
            CGContextBeginPath(c); tri(c, CGPointMake(-9, -8), CGPointMake(-9, 8), CGPointMake(0, 0));
            CGContextAddRect(c, CGRectMake(2.5, -8, 3.4, 16)); CGContextAddRect(c, CGRectMake(8, -8, 3.4, 16));
            fillAndShadow(c, color, engraved);
            break; }
        case TVGlyphRewind: { CGContextBeginPath(c); tri(c, CGPointMake(0, -8), CGPointMake(0, 8), CGPointMake(-10, 0)); tri(c, CGPointMake(10, -8), CGPointMake(10, 8), CGPointMake(0, 0)); fillAndShadow(c, color, engraved); break; }
        case TVGlyphForward: { CGContextBeginPath(c); tri(c, CGPointMake(0, -8), CGPointMake(0, 8), CGPointMake(10, 0)); tri(c, CGPointMake(-10, -8), CGPointMake(-10, 8), CGPointMake(0, 0)); fillAndShadow(c, color, engraved); break; }
        case TVGlyphNext: { CGContextBeginPath(c); tri(c, CGPointMake(-8, -8), CGPointMake(-8, 8), CGPointMake(4, 0)); CGContextAddRect(c, CGRectMake(5.5, -8, 3.4, 16)); fillAndShadow(c, color, engraved); break; }
        case TVGlyphPrev: { CGContextBeginPath(c); tri(c, CGPointMake(8, -8), CGPointMake(8, 8), CGPointMake(-4, 0)); CGContextAddRect(c, CGRectMake(-8.9, -8, 3.4, 16)); fillAndShadow(c, color, engraved); break; }
        case TVGlyphStop: { CGContextBeginPath(c); CGContextAddRect(c, CGRectMake(-7, -7, 14, 14)); fillAndShadow(c, color, engraved); break; }
        case TVGlyphKeyboard: {
            CGContextSetLineWidth(c, 2);
            TVRoundRectPath(c, CGRectMake(-11, -7.5, 22, 15), 2.5); CGContextStrokePath(c);
            for (int i = 0; i < 4; i++) CGContextAddRect(c, CGRectMake(-8.5 + i * 4.6, -4.5, 2.6, 2.4));
            for (int i = 0; i < 3; i++) CGContextAddRect(c, CGRectMake(-6.2 + i * 4.6, -0.6, 2.6, 2.4));
            CGContextAddRect(c, CGRectMake(-5.5, 3.2, 11, 2.2));
            fillAndShadow(c, color, NO);
            break; }
        case TVGlyphSearch: {
            CGContextSetLineWidth(c, 2.8);
            CGContextAddEllipseInRect(c, CGRectMake(-9, -9, 13, 13)); CGContextStrokePath(c);
            CGContextMoveToPoint(c, 2, 2); CGContextAddLineToPoint(c, 9, 9); CGContextStrokePath(c);
            break; }
        case TVGlyphDelete: {
            CGContextSetLineWidth(c, 2);
            CGContextMoveToPoint(c, -11, 0); CGContextAddLineToPoint(c, -5, -7.5); CGContextAddLineToPoint(c, 10, -7.5); CGContextAddLineToPoint(c, 10, 7.5); CGContextAddLineToPoint(c, -5, 7.5); CGContextClosePath(c); CGContextStrokePath(c);
            CGContextMoveToPoint(c, -1, -3.5); CGContextAddLineToPoint(c, 5, 3.5); CGContextMoveToPoint(c, 5, -3.5); CGContextAddLineToPoint(c, -1, 3.5); CGContextStrokePath(c);
            break; }
        case TVGlyphReturn: {
            CGContextMoveToPoint(c, 9, -7); CGContextAddLineToPoint(c, 9, 2); CGContextAddLineToPoint(c, -7, 2); CGContextStrokePath(c);
            CGContextMoveToPoint(c, -2, -3); CGContextAddLineToPoint(c, -8, 2); CGContextAddLineToPoint(c, -2, 7); CGContextStrokePath(c);
            break; }
        case TVGlyphRemote: {
            CGContextSetLineWidth(c, 2.2);
            CGContextAddEllipseInRect(c, CGRectMake(-10, -10, 20, 20)); CGContextStrokePath(c);
            CGContextAddEllipseInRect(c, CGRectMake(-3.5, -3.5, 7, 7)); CGContextStrokePath(c);
            CGContextBeginPath(c); tri(c, CGPointMake(0, -9.5), CGPointMake(-2.4, -6.5), CGPointMake(2.4, -6.5)); tri(c, CGPointMake(0, 9.5), CGPointMake(-2.4, 6.5), CGPointMake(2.4, 6.5));
            fillAndShadow(c, color, NO);
            break; }
        case TVGlyphPad: {
            CGContextSetLineWidth(c, 2.2);
            TVRoundRectPath(c, CGRectMake(-10, -8, 20, 16), 4); CGContextStrokePath(c);
            CGContextAddEllipseInRect(c, CGRectMake(-2, -2, 4, 4)); fillAndShadow(c, color, NO);
            break; }
        case TVGlyphMore: {
            for (int i = -1; i <= 1; i++) CGContextAddEllipseInRect(c, CGRectMake(i * 7 - 2.4, -2.4, 4.8, 4.8));
            fillAndShadow(c, color, NO);
            break; }
        default: break;
    }
    CGContextRestoreGState(c);
}

/* ---------- haptic ---------- */

typedef void (*TVVibeFn)(SystemSoundID, id, NSDictionary *);

void TVHaptic(void) {
    static TVVibeFn fn; static BOOL looked; static NSDictionary *tick;
    if (!looked) {
        looked = YES;
        fn = (TVVibeFn)dlsym(RTLD_DEFAULT, "AudioServicesPlaySystemSoundWithVibration");
        tick = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSArray arrayWithObjects:[NSNumber numberWithBool:YES], [NSNumber numberWithInt:25], nil], @"VibePattern",
                [NSNumber numberWithFloat:1.0f], @"Intensity", nil];
    }
    if (fn) fn(kSystemSoundID_Vibrate, nil, tick);
    else AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}
