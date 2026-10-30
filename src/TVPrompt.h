#import <UIKit/UIKit.h>

/* In-app replacement for UIAlertView (a tweak on the phone swallows the real one): a small black plastic panel with text fields and keys.
   fields: dictionaries with @"text", @"placeholder", @"secure" (NSNumber), @"hex" (NSNumber: upper-case, no autocorrect, for pairing codes).
   buttons: titles, the first one cancels. The handler gets the tapped button index and the text of every field. */
typedef void (^TVPromptHandler)(NSInteger button, NSArray *texts);

@interface TVPrompt : UIView
+ (TVPrompt *)showTitle:(NSString *)title message:(NSString *)message fields:(NSArray *)fields buttons:(NSArray *)buttons handler:(TVPromptHandler)handler;
- (void)dismiss;   /* closes it without calling the handler */
@end
