#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

void SCLSetAudioDataDelegate(AVCaptureAudioDataOutput *output, id _Nullable delegate, dispatch_queue_t _Nullable queue);

@interface SCLAudioPump : NSObject

+ (instancetype)shared;

- (void)sessionStatesDidChange;

@end

NS_ASSUME_NONNULL_END
