#import <UIKit/UIKit.h>
#import "TVStyle.h"

extern NSString *const TVNotConnected;      /* posted when a key could not be sent because there is no live TV */

/* sends a key to the TV; posts TVNotConnected when it cannot */
void TVPress(int keyCode);

/* base of the pressable parts: reacts on touch-down (like a real remote), repeats while held when asked */
@interface TVPad : UIControl
@property (nonatomic) BOOL repeats;
- (NSInteger)zoneAtPoint:(CGPoint)p;        /* -1: not a hit */
- (void)fireZone:(NSInteger)zone;
- (BOOL)zoneRepeats:(NSInteger)zone;
@property (nonatomic, readonly) NSInteger pressedZone;
@end

@interface TVKeyButton : TVPad
@property (nonatomic) TVGlyph glyph;
@property (nonatomic, copy) NSString *label;
@property (nonatomic) TVPlastic plastic;
@property (nonatomic) int keyCode;          /* 0: only send ValueChanged, no key */
@property (nonatomic) BOOL lit;
@property (nonatomic) CGFloat radius;       /* 0: fully round ends */
+ (TVKeyButton *)keyWithGlyph:(TVGlyph)g label:(NSString *)label plastic:(TVPlastic)p key:(int)code;
@end

@interface TVDPad : TVPad @end              /* chrome ring, four arrows and a glossy OK */

@interface TVRocker : TVPad                 /* two halves, top and bottom, like a volume or channel rocker */
@property (nonatomic, copy) NSString *label;
@property (nonatomic) TVGlyph topGlyph, bottomGlyph;
@property (nonatomic) int topKey, bottomKey;
@end

@interface TVStatusPlate : UIControl        /* brushed plate with the TV's name and a status lamp */
@end

@interface TVTouchpad : UIView              /* swipes become arrow keys, a tap is OK, a two-finger tap is Back */
@end

@interface TVPageSwitch : UIControl
@property (nonatomic) NSInteger selectedIndex;
/* a tab bar: each tab is a glyph over a short title, the selected one lit amber */
- (id)initWithTitles:(NSArray *)titles glyphs:(NSArray *)glyphs;      /* glyphs: NSNumber(TVGlyph) */
@end
