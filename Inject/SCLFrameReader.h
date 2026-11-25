#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import "SCLSharedMemory.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCLFrameReader : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) BOOL hostAlive;
@property (nonatomic, readonly) uint32_t deviceProfile;
@property (nonatomic, readonly) BOOL asksForPermission;
/// Whether the picture turns with the simulated device like a real sensor; on unless the host turns it off.
@property (nonatomic, readonly) BOOL followsDeviceRotation;

- (uint64_t)frameCounterForStream:(int)stream;
- (nullable CVPixelBufferRef)copyFrameForStream:(int)stream CF_RETURNS_RETAINED;
- (void)reportCameraState:(uint32_t)state width:(uint32_t)width height:(uint32_t)height;
- (void)reportFrameDelivered;
- (void)reportPhotoCaptured;
- (void)startHeartbeat;

@end

NS_ASSUME_NONNULL_END
