#import "TVMainController.h"
#import "TVStyle.h"
#import "TVControls.h"
#import "TVRemote.h"
#import "TVStore.h"
#import "TVProto.h"
#import "TVDevicesSheet.h"
#import "TVPrompt.h"

/* ---------- app tile ---------- */

@interface TVAppTile : TVPad
@property (nonatomic, copy) NSString *name, *link;
@property (nonatomic, strong) UIColor *badge;
@property (nonatomic) BOOL isAdd;
@end

@implementation TVAppTile
- (void)fireZone:(NSInteger)zone { [self sendActionsForControlEvents:UIControlEventValueChanged]; }
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect r = CGRectInset(self.bounds, 3, 3);
    BOOL down = self.pressedZone >= 0;
    TVDrawKey(c, r, 12, TVPlasticDark, down, NO);
    CGFloat dy = down ? 1 : 0;
    CGRect disc = CGRectMake(CGRectGetMidX(r) - 18, r.origin.y + 9 + dy, 36, 36);
    if (self.isAdd) {
        TVDrawGlyph(c, TVGlyphPlus, disc, TVRGB(200, 202, 208), YES);
    } else {
        CGContextSaveGState(c);
        CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 2, TVRGBA(0, 0, 0, 0.9).CGColor);
        CGContextAddEllipseInRect(c, disc); CGContextClip(c);
        CGFloat rr, gg, bb, aa; [self.badge getRed:&rr green:&gg blue:&bb alpha:&aa];
        TVFillGradient(c, disc, [UIColor colorWithRed:MIN(1, rr + 0.25) green:MIN(1, gg + 0.25) blue:MIN(1, bb + 0.25) alpha:1], [UIColor colorWithRed:rr * 0.6 green:gg * 0.6 blue:bb * 0.6 alpha:1]);
        TVFillGradient(c, CGRectMake(disc.origin.x, disc.origin.y, 36, 17), TVRGBA(255, 255, 255, 0.35), TVRGBA(255, 255, 255, 0.02));
        CGContextRestoreGState(c);
        NSString *ini = self.name.length ? [[self.name substringToIndex:1] uppercaseString] : @"?";
        TVDrawText(ini, CGRectMake(disc.origin.x, disc.origin.y + 6, 36, 24), TVFont(@"HelveticaNeue-Bold", 21), [UIColor whiteColor], TVRGBA(0, 0, 0, 0.55), -1, NSTextAlignmentCenter);
    }
    TVDrawText(self.name, CGRectMake(r.origin.x + 3, CGRectGetMaxY(r) - 25 + dy, r.size.width - 6, 16), TVFont(@"HelveticaNeue-Bold", 11.5), TVRGB(226, 228, 233), TVRGBA(0, 0, 0, 0.9), -1, NSTextAlignmentCenter);
}
@end

/* ---------- the LCD-like typing field ---------- */

@interface TVWellView : UIView @end
@implementation TVWellView
- (id)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; self.userInteractionEnabled = NO; } return self; }
- (void)drawRect:(CGRect)r { TVDrawWell(UIGraphicsGetCurrentContext(), CGRectInset(self.bounds, 2, 2), 10); }
@end

/* ---------- controller ---------- */

@interface TVMainController () <UITextFieldDelegate>
@property (nonatomic, strong) UIView *remotePage, *padPage, *appsPage, *keysPage, *morePage;
@property (nonatomic, strong) TVPageSwitch *pages;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UILabel *keysNote;
@property (nonatomic, copy) NSArray *pageViews;
@property (nonatomic, strong) NSMutableArray *customApps;
@end

static const CGFloat PAGE_Y = 78, PAGE_H = 402;
#define PW 288          /* width of the faceplate and of every page */
#define BODY CGRectMake(16, 8, PW, 500)

@implementation TVMainController

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotate { return NO; }
- (NSUInteger)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }

- (void)viewDidLoad {
    [super viewDidLoad];
    CGSize sz = self.view.bounds.size;
    UIImageView *wood = [[UIImageView alloc] initWithImage:TVWoodImage(sz)];
    wood.frame = self.view.bounds; wood.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:wood];
    CGRect body = BODY;
    UIImageView *plate = [[UIImageView alloc] initWithImage:TVFaceplateImage(CGSizeMake(body.size.width + 2 * TVFaceMargin, body.size.height + 2 * TVFaceMargin))];
    plate.frame = CGRectMake(body.origin.x - TVFaceMargin, body.origin.y - TVFaceMargin, plate.image.size.width, plate.image.size.height);
    [self.view addSubview:plate];

    [self buildHeader];
    self.remotePage = [self page]; self.padPage = [self page]; self.appsPage = [self page]; self.keysPage = [self page]; self.morePage = [self page];
    self.pageViews = [NSArray arrayWithObjects:self.remotePage, self.padPage, self.appsPage, self.keysPage, self.morePage, nil];
    [self buildRemote]; [self buildPad]; [self buildApps]; [self buildKeys]; [self buildMore];

    self.pages = [[TVPageSwitch alloc] initWithTitles:[NSArray arrayWithObjects:@"REMOTE", @"PAD", @"APPS", @"KEYS", @"MORE", nil]
                                                  glyphs:[NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphRemote], [NSNumber numberWithInt:TVGlyphPad], [NSNumber numberWithInt:TVGlyphGuide], [NSNumber numberWithInt:TVGlyphKeyboard], [NSNumber numberWithInt:TVGlyphMore], nil]];
    self.pages.frame = CGRectMake(0, sz.height - 49, sz.width, 49);
    [self.pages addTarget:self action:@selector(pageChanged) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.pages];
    NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:@"page"];
    self.pages.selectedIndex = saved >= 0 && saved < 5 ? saved : 0;
    [self pageChanged];
}

- (UIView *)page {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(BODY.origin.x, PAGE_Y, BODY.size.width, PAGE_H)];
    v.backgroundColor = [UIColor clearColor];
    [self.view addSubview:v];
    return v;
}

- (void)pageChanged {
    NSInteger i = self.pages.selectedIndex;
    for (NSUInteger k = 0; k < self.pageViews.count; k++) [[self.pageViews objectAtIndex:k] setHidden:(NSInteger)k != i];
    [self.field resignFirstResponder];
    [[NSUserDefaults standardUserDefaults] setInteger:i forKey:@"page"];
}

#pragma mark building blocks

- (TVKeyButton *)key:(TVGlyph)g label:(NSString *)l plastic:(TVPlastic)p code:(int)code frame:(CGRect)f in:(UIView *)v {
    TVKeyButton *k = [TVKeyButton keyWithGlyph:g label:l plastic:p key:code];
    k.frame = f; k.radius = 10;
    [v addSubview:k];
    return k;
}

- (void)buildHeader {
    CGRect body = BODY;
    TVStatusPlate *plate = [[TVStatusPlate alloc] initWithFrame:CGRectMake(body.origin.x + 18, 36, 206, 42)];
    [plate addTarget:self action:@selector(openDevices) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:plate];
    TVKeyButton *power = [TVKeyButton keyWithGlyph:TVGlyphPower label:nil plastic:TVPlasticRed key:TVKeyPower];
    power.frame = CGRectMake(CGRectGetMaxX(body) - 18 - 46, 34, 46, 46);
    [self.view addSubview:power];
}

/* Back and Home: the two keys nearly every screen on the TV needs */
- (void)addNavRow:(UIView *)v y:(CGFloat)y {
    CGFloat w = (PW - 32 - 14) / 2;
    [self key:TVGlyphBack label:@"BACK" plastic:TVPlasticLight code:TVKeyBack frame:CGRectMake(16, y, w, 46) in:v];
    [self key:TVGlyphHome label:@"HOME" plastic:TVPlasticLight code:TVKeyHome frame:CGRectMake(16 + w + 14, y, w, 46) in:v];
}

/* volume rocker, two keys in the middle, channel rocker */
- (void)addVolumeRow:(UIView *)v y:(CGFloat)y {
    TVRocker *vol = [[TVRocker alloc] initWithFrame:CGRectMake(18, y, 72, 96)];
    vol.label = @"VOL"; vol.topGlyph = TVGlyphPlus; vol.bottomGlyph = TVGlyphMinus; vol.topKey = TVKeyVolUp; vol.bottomKey = TVKeyVolDown;
    [v addSubview:vol];
    TVRocker *ch = [[TVRocker alloc] initWithFrame:CGRectMake(PW - 18 - 72, y, 72, 96)];
    ch.label = @"CH"; ch.topGlyph = TVGlyphChevronUp; ch.bottomGlyph = TVGlyphChevronDown; ch.topKey = TVKeyChUp; ch.bottomKey = TVKeyChDown;
    [v addSubview:ch];
    [self key:TVGlyphMute label:nil plastic:TVPlasticDark code:TVKeyMute frame:CGRectMake((PW - 80) / 2, y + 24, 80, 44) in:v];
}

- (void)buildRemote {
    UIView *v = self.remotePage;
    TVDPad *dpad = [[TVDPad alloc] initWithFrame:CGRectMake((PW - 212) / 2, 2, 212, 212)];
    [v addSubview:dpad];
    [self addNavRow:v y:226];
    [self addVolumeRow:v y:288];
}

/* a touchpad and the two keys that matter next to it */
- (void)buildPad {
    UIView *v = self.padPage;
    TVTouchpad *pad = [[TVTouchpad alloc] initWithFrame:CGRectMake(16, 0, PW - 32, 332)];
    [v addSubview:pad];
    [self addNavRow:v y:346];
}

/* everything else, out of the way */
- (void)buildMore {
    UIView *v = self.morePage;
    CGFloat w = 84, gap = (PW - 32 - 3 * w) / 2;
    NSArray *sys = [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphInput], @"INPUT", [NSNumber numberWithInt:TVKeyInput], nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphSettings], @"SETUP", [NSNumber numberWithInt:TVKeySettings], nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphInfo], @"INFO", [NSNumber numberWithInt:TVKeyInfo], nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphMenu], @"MENU", [NSNumber numberWithInt:TVKeyMenu], nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphGuide], @"GUIDE", [NSNumber numberWithInt:TVKeyGuide], nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphSearch], @"FIND", [NSNumber numberWithInt:TVKeySearch], nil], nil];
    NSArray *media = [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphPrev], @"PREV", [NSNumber numberWithInt:TVKeyPrev], nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphRewind], @"REW", [NSNumber numberWithInt:TVKeyRewind], nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphForward], @"FWD", [NSNumber numberWithInt:TVKeyForward], nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphNext], @"NEXT", [NSNumber numberWithInt:TVKeyNext], nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphPlayPause], @"PLAY", [NSNumber numberWithInt:TVKeyPlayPause], nil],
        [NSArray arrayWithObjects:[NSNumber numberWithInt:TVGlyphStop], @"STOP", [NSNumber numberWithInt:TVKeyStop], nil], nil];
    NSArray *groups = [NSArray arrayWithObjects:sys, media, nil];
    NSArray *heads = [NSArray arrayWithObjects:@"SYSTEM", @"MEDIA", nil];
    CGFloat y = 10;
    for (NSUInteger g = 0; g < groups.count; g++) {
        UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 200, 16)];
        h.backgroundColor = [UIColor clearColor]; h.text = [heads objectAtIndex:g]; h.font = TVFont(@"HelveticaNeue-Bold", 10.5);
        h.textColor = TVRGB(150, 152, 160); h.shadowColor = [UIColor blackColor]; h.shadowOffset = CGSizeMake(0, -1);
        [v addSubview:h];
        y += 20;
        NSArray *items = [groups objectAtIndex:g];
        for (NSUInteger i = 0; i < items.count; i++) {
            NSArray *it = [items objectAtIndex:i];
            [self key:(TVGlyph)[[it objectAtIndex:0] intValue] label:[it objectAtIndex:1] plastic:TVPlasticDark code:[[it objectAtIndex:2] intValue]
                frame:CGRectMake(16 + (i % 3) * (w + gap), y + (i / 3) * 54, w, 46) in:v];
        }
        y += 2 * 54 + 14;
    }
}

#pragma mark apps

- (NSArray *)builtInApps {
    return [NSArray arrayWithObjects:
        [NSArray arrayWithObjects:@"YouTube", @"https://www.youtube.com", TVRGB(224, 36, 36), nil],
        [NSArray arrayWithObjects:@"Netflix", @"https://www.netflix.com", TVRGB(190, 20, 30), nil],
        [NSArray arrayWithObjects:@"Prime Video", @"https://app.primevideo.com", TVRGB(20, 150, 230), nil],
        [NSArray arrayWithObjects:@"Disney+", @"https://www.disneyplus.com", TVRGB(30, 60, 170), nil],
        [NSArray arrayWithObjects:@"Kodi", @"market://launch?id=org.xbmc.kodi", TVRGB(20, 130, 190), nil],
        [NSArray arrayWithObjects:@"Spotify", @"https://open.spotify.com", TVRGB(30, 170, 80), nil],
        [NSArray arrayWithObjects:@"Play Store", @"https://play.google.com/store", TVRGB(60, 150, 90), nil],
        [NSArray arrayWithObjects:@"Twitch", @"https://www.twitch.tv", TVRGB(120, 70, 200), nil],
        nil];
}

- (void)buildApps {
    for (UIView *s in [self.appsPage.subviews copy]) [s removeFromSuperview];
    if (!self.customApps) self.customApps = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:@"customApps"] ?: [NSArray array]];
    NSMutableArray *tiles = [NSMutableArray array];
    for (NSArray *a in [self builtInApps]) [tiles addObject:a];
    for (NSDictionary *d in self.customApps) [tiles addObject:[NSArray arrayWithObjects:[d objectForKey:@"name"], [d objectForKey:@"link"], TVRGB(150, 110, 60), [NSNumber numberWithBool:YES], nil]];
    CGFloat tw = 80, th = 76, gap = (PW - 32 - 3 * tw) / 2;
    NSUInteger n = tiles.count + 1;       /* the last slot adds a link */
    for (NSUInteger i = 0; i < n && i < 12; i++) {
        TVAppTile *t = [[TVAppTile alloc] initWithFrame:CGRectMake(16 + (i % 3) * (tw + gap), (i / 3) * (th + 8), tw, th)];
        if (i == tiles.count) { t.isAdd = YES; t.name = @"Add link"; [t addTarget:self action:@selector(addApp) forControlEvents:UIControlEventValueChanged]; }
        else {
            NSArray *a = [tiles objectAtIndex:i];
            t.name = [a objectAtIndex:0]; t.link = [a objectAtIndex:1]; t.badge = [a objectAtIndex:2];
            [t addTarget:self action:@selector(launch:) forControlEvents:UIControlEventValueChanged];
            if (a.count > 3) {
                UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(removeApp:)];
                lp.minimumPressDuration = 0.8; t.tag = (NSInteger)(i - 8) + 1000;
                [t addGestureRecognizer:lp];
            }
        }
        [self.appsPage addSubview:t];
    }
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(16, PAGE_H - 36, PW - 32, 34)];
    hint.backgroundColor = [UIColor clearColor]; hint.numberOfLines = 2; hint.textAlignment = NSTextAlignmentCenter;
    hint.font = TVFont(@"HelveticaNeue", 10.5); hint.textColor = TVRGB(120, 122, 130);
    hint.text = @"Tap an app to open it on the TV. Long-press a link you added to remove it.";
    [self.appsPage addSubview:hint];
}

- (void)launch:(TVAppTile *)t {
    if (![[TVRemote shared] launchApp:t.link]) [[NSNotificationCenter defaultCenter] postNotificationName:TVNotConnected object:nil];
}

- (void)addApp {
    NSArray *fields = [NSArray arrayWithObjects:
        [NSDictionary dictionaryWithObjectsAndKeys:@"", @"text", @"Name", @"placeholder", nil],
        [NSDictionary dictionaryWithObjectsAndKeys:@"", @"text", @"https://… or market://launch?id=…", @"placeholder", nil], nil];
    [TVPrompt showTitle:@"Add an app link" message:@"The TV opens this link, usually in the app that handles it." fields:fields buttons:[NSArray arrayWithObjects:@"Cancel", @"Add", nil] handler:^(NSInteger b, NSArray *texts) {
        NSString *name = [[texts objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSString *link = [[texts objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (b != 1 || !name.length || !link.length) return;
        [self.customApps addObject:[NSDictionary dictionaryWithObjectsAndKeys:name, @"name", link, @"link", nil]];
        [[NSUserDefaults standardUserDefaults] setObject:self.customApps forKey:@"customApps"];
        [self buildApps];
    }];
}

- (void)removeApp:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    NSInteger idx = g.view.tag - 1000;
    if (idx < 0 || idx >= (NSInteger)self.customApps.count) return;
    NSString *name = [[self.customApps objectAtIndex:idx] objectForKey:@"name"];
    [TVPrompt showTitle:@"Remove link?" message:name fields:nil buttons:[NSArray arrayWithObjects:@"Keep", @"Remove", nil] handler:^(NSInteger b, NSArray *t) {
        if (b != 1) return;
        [self.customApps removeObjectAtIndex:idx];
        [[NSUserDefaults standardUserDefaults] setObject:self.customApps forKey:@"customApps"];
        [self buildApps];
    }];
}

#pragma mark keyboard

- (void)buildKeys {
    UIView *v = self.keysPage;
    TVWellView *well = [[TVWellView alloc] initWithFrame:CGRectMake(16, 0, PW - 32, 58)];
    [v addSubview:well];
    self.field = [[UITextField alloc] initWithFrame:CGRectMake(30, 14, PW - 60, 30)];
    self.field.backgroundColor = [UIColor clearColor];
    self.field.textColor = TVRGB(255, 190, 70); self.field.font = TVFont(@"Courier-Bold", 20);
    self.field.placeholder = @"type to send to the TV";
    self.field.autocorrectionType = UITextAutocorrectionTypeNo; self.field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.field.keyboardAppearance = UIKeyboardAppearanceAlert; self.field.returnKeyType = UIReturnKeySend;
    self.field.delegate = self;
    [v addSubview:self.field];
    CGFloat w = 56, gap = (PW - 32 - 4 * w) / 3;
    TVKeyButton *k;
    k = [self key:TVGlyphKeyboard label:nil plastic:TVPlasticAmber code:0 frame:CGRectMake(16, 68, w, 40) in:v];
    [k addTarget:self action:@selector(showKeyboard) forControlEvents:UIControlEventValueChanged];
    [self key:TVGlyphDelete label:nil plastic:TVPlasticDark code:TVKeyDel frame:CGRectMake(16 + (w + gap), 68, w, 40) in:v];
    [self key:TVGlyphReturn label:nil plastic:TVPlasticDark code:TVKeyEnter frame:CGRectMake(16 + 2 * (w + gap), 68, w, 40) in:v];
    [self key:TVGlyphSearch label:nil plastic:TVPlasticDark code:TVKeySearch frame:CGRectMake(16 + 3 * (w + gap), 68, w, 40) in:v];
    UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(16, 120, PW - 32, 120)];
    note.backgroundColor = [UIColor clearColor]; note.numberOfLines = 0; note.textAlignment = NSTextAlignmentCenter;
    note.font = TVFont(@"HelveticaNeue", 11.5); note.textColor = TVRGB(120, 122, 130);
    note.text = @"Tap the amber key for the keyboard. Each letter is sent to the TV as soon as you type it, so open a search box on the TV first. Capitals, accents and symbols the TV has no key for are skipped or simplified.";
    [v addSubview:note];
}

- (void)showKeyboard { [self.field becomeFirstResponder]; }

/* Android key codes for the plain characters; the TV has no text-field API here, so typing is key presses */
static int keyForChar(unichar ch) {
    if (ch >= 'a' && ch <= 'z') return 29 + (ch - 'a');
    if (ch >= '0' && ch <= '9') return 7 + (ch - '0');
    switch (ch) { case ' ': return 62; case '.': return 56; case ',': return 55; case '-': return 69; case '/': return 76; case '@': return 77; case '+': return 81; case '=': return 70; case '\'': return 75; case ';': return 74; case '\\': return 73; }
    return 0;
}

- (BOOL)textField:(UITextField *)f shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)s {
    for (NSUInteger i = 0; i < range.length; i++) TVPress(TVKeyDel);       /* removing text = backspaces */
    NSString *folded = [[s lowercaseString] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en"]];
    folded = [folded stringByReplacingOccurrencesOfString:@"ı" withString:@"i"];
    for (NSUInteger i = 0; i < folded.length; i++) { int code = keyForChar([folded characterAtIndex:i]); if (code) TVPress(code); }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)f { TVPress(TVKeyEnter); f.text = @""; return NO; }

#pragma mark devices

- (void)openDevices {
    [self.field resignFirstResponder];
    [TVDevicesSheet showInView:self.view];
}

@end
