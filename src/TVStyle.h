#import <UIKit/UIKit.h>

/* Everything the remote is made of, drawn in code: walnut wood, black plastic, rubber keys, chrome and brass. No image assets. */

UIColor *TVRGB(int r, int g, int b);
UIColor *TVRGBA(int r, int g, int b, CGFloat a);
UIFont *TVFont(NSString *name, CGFloat size);               /* falls back to the bold system font when the face is missing */

typedef NS_ENUM(NSInteger, TVGlyph) {
    TVGlyphNone, TVGlyphPower, TVGlyphBack, TVGlyphHome, TVGlyphMenu, TVGlyphInfo, TVGlyphInput, TVGlyphSettings, TVGlyphGuide,
    TVGlyphPlus, TVGlyphMinus, TVGlyphMute, TVGlyphChevronUp, TVGlyphChevronDown, TVGlyphPlayPause, TVGlyphRewind, TVGlyphForward,
    TVGlyphNext, TVGlyphPrev, TVGlyphStop, TVGlyphKeyboard, TVGlyphSearch, TVGlyphDelete, TVGlyphReturn, TVGlyphRemote, TVGlyphPad, TVGlyphMore
};

typedef NS_ENUM(NSInteger, TVPlastic) { TVPlasticDark, TVPlasticLight, TVPlasticRed, TVPlasticAmber };

UIImage *TVWoodImage(CGSize size);                           /* cached; walnut with the grain running along the long side */
UIImage *TVFaceplateImage(CGSize size);                      /* black glossy plastic with a bevel and brass screws; has a transparent margin of TVFaceMargin for its shadow */
extern const CGFloat TVFaceMargin;

void TVRoundRectPath(CGContextRef c, CGRect r, CGFloat radius);
void TVFillGradient(CGContextRef c, CGRect r, UIColor *top, UIColor *bottom);
/* a plastic key: body gradient, specular gloss on the upper half, rim light, drop shadow when raised */
void TVDrawKey(CGContextRef c, CGRect r, CGFloat radius, TVPlastic kind, BOOL pressed, BOOL lit);
void TVDrawCircleKey(CGContextRef c, CGRect r, TVPlastic kind, BOOL pressed, BOOL lit);
/* brushed metal plate with a bevel */
void TVDrawPlate(CGContextRef c, CGRect r, CGFloat radius);
/* recessed dark well (a slot the keys sit in) */
void TVDrawWell(CGContextRef c, CGRect r, CGFloat radius);
void TVDrawGlyph(CGContextRef c, TVGlyph g, CGRect r, UIColor *color, BOOL engraved);
void TVDrawText(NSString *s, CGRect r, UIFont *font, UIColor *color, UIColor *shadow, CGFloat shadowDY, NSTextAlignment align);
void TVDrawEngraved(NSString *s, CGRect r, UIFont *font, NSTextAlignment align);     /* lettering printed on the plastic */

void TVHaptic(void);       /* one short vibration tick, where the phone can */
