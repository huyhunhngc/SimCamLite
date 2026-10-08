#import <AVFoundation/AVFoundation.h>
#import "SCLSessionState.h"

NS_ASSUME_NONNULL_BEGIN

void SCLSetVideoDataDelegate(AVCaptureVideoDataOutput *output, id _Nullable delegate, dispatch_queue_t _Nullable queue);
id _Nullable SCLVideoDataDelegate(AVCaptureVideoDataOutput *output);
dispatch_queue_t _Nullable SCLVideoDataQueue(AVCaptureVideoDataOutput *output);
void SCLSetVideoDataSettings(AVCaptureVideoDataOutput *output, NSDictionary<NSString *, id> *_Nullable settings);
NSDictionary<NSString *, id> *SCLVideoDataSettings(AVCaptureVideoDataOutput *output);

@interface SCLFramePump : NSObject

+ (instancetype)shared;

- (void)sessionStatesDidChange;
- (void)capturePhotoWithOutput:(AVCapturePhotoOutput *)output
                      settings:(AVCapturePhotoSettings *)settings
                      delegate:(id<AVCapturePhotoCaptureDelegate>)delegate
                       session:(AVCaptureSession *)session
                 maxDimensions:(CMVideoDimensions)maxDimensions;

@end

NS_ASSUME_NONNULL_END
