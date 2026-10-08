#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>

NS_ASSUME_NONNULL_BEGIN

@class SCLFakeDeviceInput;

@interface SCLFakeFrameRateRange : AVFrameRateRange
@end

@interface SCLFakeFormat : AVCaptureDeviceFormat
- (instancetype)sclInitWithMaxZoom:(CGFloat)maxZoom __attribute__((objc_method_family(init)));
@end

@interface SCLFakeDevice : AVCaptureDevice

- (instancetype)sclInitWithType:(AVCaptureDeviceType)type
                       position:(AVCaptureDevicePosition)position
                       uniqueID:(NSString *)uniqueID
                           name:(NSString *)name
                       baseCrop:(CGFloat)baseCrop
                        maxZoom:(CGFloat)maxZoom
                     switchOver:(NSArray<NSNumber *> *)switchOver
                   constituents:(NSArray<AVCaptureDevice *> *)constituents
                displayMultiplier:(CGFloat)displayMultiplier __attribute__((objc_method_family(init)));

@property (nonatomic, readonly) int sclStream;
@property (nonatomic, readonly) CGFloat sclSensorCrop;
@property (nonatomic) CGFloat sclReferenceCrop;
@property (nonatomic, readonly) CGFloat sclFrameCrop;
@property (nonatomic, readonly) float sclExposureBias;
@property (nonatomic, readonly) NSString *sclLensModel;
@property (nonatomic, readonly) double sclFocalLength;
@property (nonatomic, strong, readonly) SCLFakeDeviceInput *sclInput;

- (void)sclStepRampWithInterval:(NSTimeInterval)interval;

@end

@interface SCLFakeInputPort : AVCaptureInputPort
- (instancetype)sclInitWithInput:(AVCaptureInput *)input device:(SCLFakeDevice *)device __attribute__((objc_method_family(init)));
@end

@interface SCLFakeDeviceInput : AVCaptureDeviceInput
- (instancetype)sclInitWithDevice:(SCLFakeDevice *)device __attribute__((objc_method_family(init)));
@end

typedef NS_ENUM(NSInteger, SCLConnectionKind) {
    SCLConnectionKindVideoData,
    SCLConnectionKindPhoto,
    SCLConnectionKindPreview,
    SCLConnectionKindOther,
};

@interface SCLFakeConnection : AVCaptureConnection
- (instancetype)sclInitWithKind:(SCLConnectionKind)kind
                         output:(nullable AVCaptureOutput *)output
                   previewLayer:(nullable AVCaptureVideoPreviewLayer *)previewLayer
                        session:(AVCaptureSession *)session __attribute__((objc_method_family(init)));
@property (nonatomic, readonly) SCLConnectionKind sclKind;
@property (nonatomic, readonly, weak, nullable) AVCaptureSession *sclSession;
- (BOOL)sclEffectiveMirroredForDevice:(nullable SCLFakeDevice *)device;
@end

API_AVAILABLE(ios(17.0))
@interface SCLFakeRotationCoordinator : AVCaptureDeviceRotationCoordinator
- (instancetype)sclInitWithDevice:(SCLFakeDevice *)device previewLayer:(nullable CALayer *)previewLayer __attribute__((objc_method_family(init)));
@end

@interface SCLFakeResolvedPhotoSettings : AVCaptureResolvedPhotoSettings
- (instancetype)sclInitWithUniqueID:(int64_t)uniqueID
                         dimensions:(CMVideoDimensions)dimensions
                       flashEnabled:(BOOL)flashEnabled __attribute__((objc_method_family(init)));
@end

@interface SCLFakePhoto : AVCapturePhoto
- (instancetype)sclInitWithData:(NSData *)data
                        cgImage:(CGImageRef)cgImage
                       metadata:(NSDictionary<NSString *, id> *)metadata
                resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings
                      timestamp:(CMTime)timestamp
                     deviceType:(AVCaptureDeviceType)deviceType __attribute__((objc_method_family(init)));
@end

void SCLInstallFakeDeallocs(void);

NS_ASSUME_NONNULL_END
