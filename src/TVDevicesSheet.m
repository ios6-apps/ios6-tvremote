#import "TVDevicesSheet.h"
#import "TVStyle.h"
#import "TVControls.h"
#import "TVDiscovery.h"
#import "TVPairing.h"
#import "TVPrompt.h"
#import "TVRemote.h"
#import "TVStore.h"

/* one table row, drawn as a slot with the TV's name, its address and a status */
@interface TVRowView : UIView
@property (nonatomic, copy) NSString *name, *detail, *badge;
@property (nonatomic) BOOL good;
@end

@implementation TVRowView
- (id)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; self.contentMode = UIViewContentModeRedraw; } return self; }
- (void)drawRect:(CGRect)rect {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect r = CGRectInset(self.bounds, 0, 3);
    TVDrawWell(c, r, 9);
    TVDrawText(self.name, CGRectMake(14, r.origin.y + 6, r.size.width - 120, 20), TVFont(@"HelveticaNeue-Bold", 15), TVRGB(236, 238, 242), TVRGBA(0, 0, 0, 0.9), -1, NSTextAlignmentLeft);
    TVDrawText(self.detail, CGRectMake(14, r.origin.y + 26, r.size.width - 120, 15), TVFont(@"HelveticaNeue", 11.5), TVRGB(150, 152, 160), nil, 0, NSTextAlignmentLeft);
    UIColor *col = self.good ? TVRGB(90, 235, 120) : TVRGB(255, 176, 60);
    TVDrawText(self.badge, CGRectMake(r.size.width - 108, CGRectGetMidY(r) - 8, 98, 16), TVFont(@"HelveticaNeue-Bold", 11), col, TVRGBA(0, 0, 0, 0.9), -1, NSTextAlignmentRight);
}
@end

@interface TVDevicesSheet () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) TVDiscovery *discovery;
@property (nonatomic, strong) TVPairing *pairing;
@property (nonatomic, strong) TVPrompt *codePrompt;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, strong) TVKeyButton *scanKey;
@property (nonatomic, copy) NSArray *rows;
@end

@implementation TVDevicesSheet

+ (TVDevicesSheet *)showInView:(UIView *)parent {
    TVDevicesSheet *s = [[TVDevicesSheet alloc] initWithFrame:parent.bounds];
    [parent addSubview:s];
    s.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ s.alpha = 1; }];
    return s;
}

- (id)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor clearColor];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        /* the panel replaces the remote's faceplate, same place and size, so it reads as the remote showing another page */
        CGRect body = CGRectMake(16, 8, 288, 500);
        UIImageView *plate = [[UIImageView alloc] initWithImage:TVFaceplateImage(CGSizeMake(body.size.width + 2 * TVFaceMargin, body.size.height + 2 * TVFaceMargin))];
        plate.frame = CGRectMake(body.origin.x - TVFaceMargin, body.origin.y - TVFaceMargin, plate.image.size.width, plate.image.size.height);
        [self addSubview:plate];
        CGFloat x = 32, w = 256;
        UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(x, 34, w, 26)];
        t.backgroundColor = [UIColor clearColor]; t.text = @"YOUR TVs"; t.textAlignment = NSTextAlignmentCenter;
        t.font = TVFont(@"HelveticaNeue-Bold", 16); t.textColor = TVRGB(176, 178, 184); t.shadowColor = [UIColor blackColor]; t.shadowOffset = CGSizeMake(0, -1);
        [self addSubview:t];
        self.status = [[UILabel alloc] initWithFrame:CGRectMake(x, 60, w, 32)];
        self.status.backgroundColor = [UIColor clearColor]; self.status.numberOfLines = 2; self.status.textAlignment = NSTextAlignmentCenter;
        self.status.font = TVFont(@"HelveticaNeue", 11.5); self.status.textColor = TVRGB(150, 152, 160);
        [self addSubview:self.status];
        self.table = [[UITableView alloc] initWithFrame:CGRectMake(x - 4, 98, w + 8, 330) style:UITableViewStylePlain];
        self.table.backgroundColor = [UIColor clearColor]; self.table.separatorStyle = UITableViewCellSeparatorStyleNone;
        self.table.dataSource = self; self.table.delegate = self; self.table.rowHeight = 56;
        [self addSubview:self.table];
        CGFloat by = 440, bw = (w - 16) / 3;
        NSArray *names = [NSArray arrayWithObjects:@"Scan", @"Add IP", @"Close", nil];
        for (int i = 0; i < 3; i++) {
            TVKeyButton *k = [TVKeyButton keyWithGlyph:TVGlyphNone label:[names objectAtIndex:i] plastic:i == 2 ? TVPlasticAmber : TVPlasticDark key:0];
            k.frame = CGRectMake(x + i * (bw + 8), by, bw, 42); k.radius = 10; k.tag = i;
            [k addTarget:self action:@selector(bottomKey:) forControlEvents:UIControlEventValueChanged];
            [self addSubview:k];
            if (i == 0) self.scanKey = k;
        }
        self.discovery = [[TVDiscovery alloc] init];
        __weak TVDevicesSheet *me = self;
        self.discovery.onChange = ^{ [me reload]; };
        [self reload];
        [self.discovery start];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:TVRemoteChanged object:nil];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)bottomKey:(TVKeyButton *)k {
    if (k.tag == 0) { [self.discovery start]; [self reload]; }
    else if (k.tag == 1) [self addByAddress];
    else [self dismiss];
}

- (void)dismiss {
    [self.discovery stop];
    [self.pairing cancel]; self.pairing = nil;
    [self.codePrompt dismiss]; self.codePrompt = nil;
    void (^done)(void) = self.onClose; self.onClose = nil;
    [UIView animateWithDuration:0.18 animations:^{ self.alpha = 0; } completion:^(BOOL f) { [self removeFromSuperview]; if (done) done(); }];
}

#pragma mark list

- (void)reload {
    NSMutableArray *rows = [NSMutableArray array];
    TVStore *st = [TVStore shared];
    for (NSDictionary *d in st.tvs) [rows addObject:d];
    for (NSDictionary *d in self.discovery.found) {
        if ([st tvForHost:[d objectForKey:@"host"]]) continue;
        [rows addObject:[NSDictionary dictionaryWithObjectsAndKeys:[d objectForKey:@"name"], @"name", [d objectForKey:@"host"], @"host", [NSNumber numberWithBool:NO], @"paired", [NSNumber numberWithBool:YES], @"found", nil]];
    }
    self.rows = rows;
    [self.table reloadData];
    if (self.pairing) return;
    if (!rows.count) self.status.text = self.discovery.scanning ? @"Looking for Android TVs on this Wi-Fi…" : @"No TV found. Make sure the TV is on and on this Wi-Fi, then Scan, or Add IP.";
    else self.status.text = self.discovery.scanning ? @"Looking for more…  Tap a TV to use it." : @"Tap a TV to use it. Swipe a saved one to forget it.";
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return (NSInteger)self.rows.count; }

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"row"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"row"];
        cell.backgroundColor = [UIColor clearColor]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        TVRowView *rv = [[TVRowView alloc] initWithFrame:cell.contentView.bounds];
        rv.tag = 91; rv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [cell.contentView addSubview:rv];
    }
    NSDictionary *d = [self.rows objectAtIndex:ip.row];
    TVRowView *rv = (TVRowView *)[cell.contentView viewWithTag:91];
    TVRemote *tv = [TVRemote shared];
    NSString *host = [d objectForKey:@"host"];
    BOOL current = [tv.host isEqualToString:host];
    BOOL paired = [[d objectForKey:@"paired"] boolValue] && !(current && tv.unpaired);
    rv.name = [d objectForKey:@"name"]; rv.detail = host;
    if (current && tv.state == TVStateReady) { rv.badge = @"Connected"; rv.good = YES; }
    else if (current && tv.state == TVStateConnecting) { rv.badge = @"Connecting…"; rv.good = NO; }
    else if (paired) { rv.badge = @"Paired"; rv.good = YES; }
    else { rv.badge = @"Tap to pair"; rv.good = NO; }
    [rv setNeedsDisplay];
    return cell;
}

- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip { return [[TVStore shared] tvForHost:[[self.rows objectAtIndex:ip.row] objectForKey:@"host"]] != nil; }

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)s forRowAtIndexPath:(NSIndexPath *)ip {
    NSString *host = [[self.rows objectAtIndex:ip.row] objectForKey:@"host"];
    if ([[TVRemote shared].host isEqualToString:host]) [[TVRemote shared] disconnect];
    [[TVStore shared] removeTV:host];
    [self reload];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:NO];
    NSDictionary *d = [self.rows objectAtIndex:ip.row];
    NSString *host = [d objectForKey:@"host"];
    TVRemote *tv = [TVRemote shared];
    BOOL paired = [[d objectForKey:@"paired"] boolValue] && !([tv.host isEqualToString:host] && tv.unpaired);
    if (paired) {
        [TVStore shared].currentHost = host;
        [tv disconnect];
        [tv connectToHost:host];
        [self dismiss];
    } else [self pair:d];
}

#pragma mark add + pair

- (void)addByAddress {
    [TVPrompt showTitle:@"Add a TV" message:@"The TV's IP address, e.g. 192.168.1.50" fields:[NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:@"", @"text", @"192.168.1.50", @"placeholder", nil]]
                buttons:[NSArray arrayWithObjects:@"Cancel", @"Pair", nil] handler:^(NSInteger b, NSArray *texts) {
        NSString *ip = [[texts objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (b != 1 || !ip.length) return;
        [self pair:[NSDictionary dictionaryWithObjectsAndKeys:@"Android TV", @"name", ip, @"host", [NSNumber numberWithBool:NO], @"paired", nil]];
    }];
}

- (void)notice:(NSString *)title message:(NSString *)m {
    [TVPrompt showTitle:title message:m fields:nil buttons:[NSArray arrayWithObject:@"OK"] handler:nil];
}

- (void)pair:(NSDictionary *)tv {
    if (self.pairing) return;
    NSString *host = [tv objectForKey:@"host"];
    self.status.text = [NSString stringWithFormat:@"Contacting %@…", [tv objectForKey:@"name"]];
    TVStore *st = [TVStore shared];
    if (!st.certPem) self.status.text = @"Making this phone's key (first time only, can take a minute)…";
    [st ensureIdentity:^(NSString *err) {
        if (err) { self.status.text = err; [self notice:@"Could not make a key" message:err]; return; }
        if (self.pairing) return;
        TVPairing *p = [[TVPairing alloc] init];
        self.pairing = p;
        __weak TVDevicesSheet *me = self;
        p.onNeedCode = ^{ me.status.text = @"Look at the TV: it shows a 6-character code."; [me askCode:nil]; };
        p.onBadCode = ^{ [me askCode:@"That code does not match. Check the TV and try again."]; };
        p.onFailed = ^(NSString *why) {
            [me.codePrompt dismiss]; me.codePrompt = nil; me.pairing = nil;
            [me reload];
            [me notice:@"Pairing failed" message:why];
        };
        p.onDone = ^{
            me.pairing = nil; me.codePrompt = nil;
            NSMutableDictionary *saved = [NSMutableDictionary dictionaryWithDictionary:tv];
            [saved setObject:[NSNumber numberWithBool:YES] forKey:@"paired"];
            [[TVStore shared] saveTV:saved];
            [TVStore shared].currentHost = host;
            [[TVRemote shared] disconnect];
            [[TVRemote shared] connectToHost:host];
            [me dismiss];
        };
        [p startWithHost:host];
    }];
}

- (void)askCode:(NSString *)message {
    [self.codePrompt dismiss];
    self.codePrompt = [TVPrompt showTitle:@"Pairing code" message:message ?: @"Type the 6-character code the TV shows (digits and the letters A–F)."
        fields:[NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:@"", @"text", @"A1B2C3", @"placeholder", [NSNumber numberWithBool:YES], @"hex", nil]]
        buttons:[NSArray arrayWithObjects:@"Cancel", @"Pair", nil] handler:^(NSInteger b, NSArray *texts) {
        self.codePrompt = nil;
        if (b == 1) [self.pairing submitCode:[texts objectAtIndex:0]];
        else { [self.pairing cancel]; self.pairing = nil; [self reload]; }
    }];
#ifdef TV_PREVIEW
    /* the simulator build can type the code itself, read from the mock TV's file, so the whole flow runs without taps */
    if (getenv("TV_AUTOCODE") && !message) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSString *code = [NSString stringWithContentsOfFile:@"/tmp/mock_tv_code" encoding:NSUTF8StringEncoding error:nil];
            [self.codePrompt dismiss]; self.codePrompt = nil;
            [self.pairing submitCode:code];
        });
    }
#endif
}

@end
