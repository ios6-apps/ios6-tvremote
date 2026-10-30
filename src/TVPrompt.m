#import "TVPrompt.h"
#import "TVStyle.h"

@interface TVPromptKey : UIControl
@property (nonatomic, copy) NSString *title;
@property (nonatomic) BOOL primary;
@end

@implementation TVPromptKey
- (id)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.opaque = NO; } return self; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)r {
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect b = CGRectInset(self.bounds, 2, 2);
    TVDrawKey(c, b, 9, self.primary ? TVPlasticAmber : TVPlasticDark, self.highlighted, NO);
    UIColor *ink = self.primary ? TVRGB(60, 30, 4) : TVRGB(228, 230, 234);
    TVDrawText(self.title, CGRectMake(4, (self.bounds.size.height - 18) / 2 + (self.highlighted ? 1 : 0), self.bounds.size.width - 8, 20), TVFont(@"HelveticaNeue-Bold", 15), ink, self.primary ? TVRGBA(255, 225, 160, 0.7) : TVRGBA(0, 0, 0, 0.9), self.primary ? 1 : -1, NSTextAlignmentCenter);
}
@end

@interface TVPrompt () <UITextFieldDelegate>
@property (nonatomic, copy) TVPromptHandler handler;
@property (nonatomic, strong) NSMutableArray *inputs;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, copy) NSString *title, *message;
@end

@implementation TVPrompt

+ (TVPrompt *)showTitle:(NSString *)title message:(NSString *)message fields:(NSArray *)fields buttons:(NSArray *)buttons handler:(TVPromptHandler)handler {
    UIWindow *w = [[UIApplication sharedApplication] keyWindow] ?: [[[UIApplication sharedApplication] windows] lastObject];
    if (!w) return nil;
    TVPrompt *p = [[TVPrompt alloc] initWithFrame:w.bounds];
    p.title = title; p.message = message; p.handler = handler;
    [p build:fields buttons:buttons];
    [w addSubview:p];
    p.alpha = 0;
    [UIView animateWithDuration:0.18 animations:^{ p.alpha = 1; }];
    [[p.inputs firstObject] becomeFirstResponder];
    return p;
}

- (void)dismiss {
    self.handler = nil;
    [self endEditing:YES];
    [UIView animateWithDuration:0.15 animations:^{ self.alpha = 0; } completion:^(BOOL done) { [self removeFromSuperview]; }];
}

- (void)build:(NSArray *)fields buttons:(NSArray *)buttons {
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CGFloat pw = 284, y = 20;
    CGSize ms = [self.message sizeWithFont:TVFont(@"HelveticaNeue", 14) constrainedToSize:CGSizeMake(pw - 44, 200) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat ph = 20 + 24 + 8 + (self.message.length ? ms.height + 12 : 0) + fields.count * 44 + 48 + 20;
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake((self.bounds.size.width - pw) / 2, 50, pw, ph)];
    panel.backgroundColor = [UIColor clearColor];
    self.panel = panel;
    [self addSubview:panel];

    UIGraphicsBeginImageContextWithOptions(panel.bounds.size, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect body = CGRectInset(panel.bounds, 6, 6);
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 4), 10, TVRGBA(0, 0, 0, 0.9).CGColor);
    TVRoundRectPath(c, body, 16); CGContextSetFillColorWithColor(c, TVRGB(10, 10, 11).CGColor); CGContextFillPath(c);
    CGContextRestoreGState(c);
    CGContextSaveGState(c);
    TVRoundRectPath(c, body, 16); CGContextClip(c);
    TVFillGradient(c, body, TVRGB(58, 59, 64), TVRGB(18, 18, 20));
    TVFillGradient(c, CGRectMake(body.origin.x, body.origin.y, body.size.width, body.size.height * 0.4), TVRGBA(255, 255, 255, 0.10), TVRGBA(255, 255, 255, 0.0));
    CGContextRestoreGState(c);
    TVRoundRectPath(c, CGRectInset(body, 0.5, 0.5), 16);
    CGContextSetStrokeColorWithColor(c, TVRGBA(255, 255, 255, 0.28).CGColor); CGContextSetLineWidth(c, 1); CGContextStrokePath(c);
    UIImageView *bg = [[UIImageView alloc] initWithFrame:panel.bounds];
    bg.image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [panel addSubview:bg];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(22, y, pw - 44, 24)];
    t.text = self.title; t.textAlignment = NSTextAlignmentCenter; t.backgroundColor = [UIColor clearColor];
    t.font = TVFont(@"HelveticaNeue-Bold", 18); t.textColor = TVRGB(236, 238, 242); t.shadowColor = [UIColor blackColor]; t.shadowOffset = CGSizeMake(0, -1);
    [panel addSubview:t];
    y += 24 + 8;
    if (self.message.length) {
        UILabel *m = [[UILabel alloc] initWithFrame:CGRectMake(22, y, pw - 44, ms.height)];
        m.text = self.message; m.numberOfLines = 0; m.textAlignment = NSTextAlignmentCenter; m.backgroundColor = [UIColor clearColor];
        m.font = TVFont(@"HelveticaNeue", 14); m.textColor = TVRGB(170, 172, 180);
        [panel addSubview:m];
        y += ms.height + 12;
    }
    self.inputs = [NSMutableArray array];
    for (NSDictionary *d in fields) {
        UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(22, y, pw - 44, 34)];
        f.borderStyle = UITextBorderStyleRoundedRect;
        f.text = [d objectForKey:@"text"]; f.placeholder = [d objectForKey:@"placeholder"];
        f.secureTextEntry = [[d objectForKey:@"secure"] boolValue];
        BOOL hex = [[d objectForKey:@"hex"] boolValue];
        f.keyboardType = UIKeyboardTypeASCIICapable;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = hex ? UITextAutocapitalizationTypeAllCharacters : UITextAutocapitalizationTypeNone;
        if (hex) { f.font = TVFont(@"Courier-Bold", 22); f.textAlignment = NSTextAlignmentCenter; } else f.font = [UIFont systemFontOfSize:16];
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
        f.returnKeyType = UIReturnKeyGo;
        f.delegate = self;
        [panel addSubview:f];
        [self.inputs addObject:f];
        y += 44;
    }
    CGFloat bw = (pw - 44 - 10 * (buttons.count - 1)) / buttons.count;
    for (NSUInteger i = 0; i < buttons.count; i++) {
        TVPromptKey *b = [[TVPromptKey alloc] initWithFrame:CGRectMake(22 + i * (bw + 10), y + 4, bw, 42)];
        b.title = [buttons objectAtIndex:i]; b.primary = i > 0; b.tag = i;
        [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:b];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    NSUInteger i = [self.inputs indexOfObject:f];
    if (i + 1 < self.inputs.count) { [[self.inputs objectAtIndex:i + 1] becomeFirstResponder]; return NO; }
    [self finish:1];
    return NO;
}

- (void)tapped:(UIControl *)b { [self finish:b.tag]; }

- (void)finish:(NSInteger)idx {
    NSMutableArray *texts = [NSMutableArray array];
    for (UITextField *f in self.inputs) [texts addObject:f.text ?: @""];
    TVPromptHandler h = self.handler;
    self.handler = nil;
    [self endEditing:YES];
    [UIView animateWithDuration:0.15 animations:^{ self.alpha = 0; } completion:^(BOOL done) { [self removeFromSuperview]; }];
    if (h) h(idx, texts);
}

@end
