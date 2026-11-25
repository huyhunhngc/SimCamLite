#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceObjC.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, SCLTouchPhase) {
    SCLTouchPhaseBegan = 0,
    SCLTouchPhaseMoved = 1,
    SCLTouchPhaseEnded = 2,
};

/// Where a touch starts, so iOS treats it as a system edge gesture (a swipe up from the bottom goes Home).
typedef NS_ENUM(NSUInteger, SCLTouchEdge) {
    SCLTouchEdgeNone = 0,
    SCLTouchEdgeTop = 1,
    SCLTouchEdgeLeft = 2,
    SCLTouchEdgeBottom = 3,
    SCLTouchEdgeRight = 4,
};

/// A booted simulator's main display and HID input, reached through Apple's private CoreSimulator
/// framework: the display's IOSurface is shown as is (no screen recording) and input goes to the
/// simulator's `dtuhidd` service. Same technique as Meta's idb (FBSimulatorControl, MIT).
@interface SCLSimulatorScreen : NSObject

/// Blocks while it connects; call it off the main thread. Fails when this Xcode's CoreSimulator
/// does not offer what is needed or the simulator is not booted.
- (nullable instancetype)initWithUDID:(NSString *)udid
                         developerDir:(NSString *)developerDir
                                error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, nullable) IOSurface *surface;
/// Called on the main queue when the display's surface is replaced (boot, rotation, resize).
@property (nonatomic, copy, nullable) void (^onSurfaceChange)(IOSurface *_Nullable surface);
/// Called on the main queue after the simulator presents a new frame.
@property (nonatomic, copy, nullable) void (^onFrame)(void);

/// `x` and `y` are 0...1 from the display's top left.
- (void)sendTouch:(SCLTouchPhase)phase x:(double)x y:(double)y edge:(SCLTouchEdge)edge;
/// A USB HID keyboard usage (page 0x07).
- (void)sendKey:(uint32_t)usage down:(BOOL)down;
/// A HID consumer usage (page 0x0C): 0x40 Home, 0x30 Power.
- (void)sendButton:(uint16_t)usage down:(BOOL)down;
- (void)detach;

@end

NS_ASSUME_NONNULL_END
