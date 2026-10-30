#import <Foundation/Foundation.h>

/* Just enough protobuf for the Android TV remote protocol: write varint / string / nested fields, and parse a message into field number -> values.
   A parsed value is an NSNumber (varint) or an NSData (length-delimited: string, bytes or a nested message). */

void TVPBVarint(NSMutableData *d, int field, unsigned long long value);
void TVPBBytes(NSMutableData *d, int field, NSData *value);
void TVPBString(NSMutableData *d, int field, NSString *value);
void TVPBMessage(NSMutableData *d, int field, NSData *sub);

NSDictionary *TVPBParse(NSData *msg);       /* field number (NSNumber) -> NSArray of values; nil when malformed */
NSData *TVPBFirstData(NSDictionary *m, int field);
NSNumber *TVPBFirstNumber(NSDictionary *m, int field);
NSString *TVPBFirstString(NSDictionary *m, int field);

/* the length prefix that frames every message on the wire */
NSData *TVPBFrame(NSData *msg);
/* takes complete frames off the front of buf; returns the messages, leaves a partial frame in buf. Sets *bad when a length is absurd. */
NSArray *TVPBTakeFrames(NSMutableData *buf, BOOL *bad);

/* Android key codes the remote uses */
enum {
    TVKeyHome = 3, TVKeyBack = 4, TVKeyUp = 19, TVKeyDown = 20, TVKeyLeft = 21, TVKeyRight = 22, TVKeyCenter = 23,
    TVKeyVolUp = 24, TVKeyVolDown = 25, TVKeyPower = 26, TVKeyEnter = 66, TVKeyDel = 67, TVKeyMenu = 82, TVKeySearch = 84,
    TVKeyPlayPause = 85, TVKeyStop = 86, TVKeyNext = 87, TVKeyPrev = 88, TVKeyRewind = 89, TVKeyForward = 90,
    TVKeyMute = 164, TVKeyInfo = 165, TVKeyChUp = 166, TVKeyChDown = 167, TVKeyGuide = 172, TVKeySettings = 176, TVKeyInput = 178,
    TVKeyRed = 183, TVKeyGreen = 184, TVKeyYellow = 185, TVKeyBlue = 186
};
