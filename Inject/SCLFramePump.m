#import "SCLFramePump.h"
#import "SCLFrameReader.h"
#import "SCLRuntime.h"
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdatomic.h>

static const void *SCLVideoDelegateKey = &SCLVideoDelegateKey;
static const void *SCLVideoQueueKey = &SCLVideoQueueKey;
static const void *SCLVideoSettingsKey = &SCLVideoSettingsKey;
static const void *SCLOutputContextKey = &SCLOutputContextKey;
static const void *SCLPreviewContentKey = &SCLPreviewContentKey;
static const void *SCLPreviewBusyKey = &SCLPreviewBusyKey;
static const void *SCLPreviewFrameKey = &SCLPreviewFrameKey;

static const double SCLFrameRate = 30;
static const double SCLPollRate = 120;
static const CGFloat SCLPreviewMaxEdge = 1280;

void SCLSetVideoDataDelegate(AVCaptureVideoDataOutput *output, id delegate, dispatch_queue_t queue) {
    objc_setAssociatedObject(output, SCLVideoDelegateKey, [SCLWeakBox boxWithValue:delegate], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(output, SCLVideoQueueKey, queue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

id SCLVideoDataDelegate(AVCaptureVideoDataOutput *output) {
    SCLWeakBox *box = objc_getAssociatedObject(output, SCLVideoDelegateKey);
    return box.value;
}

dispatch_queue_t SCLVideoDataQueue(AVCaptureVideoDataOutput *output) {
    return objc_getAssociatedObject(output, SCLVideoQueueKey);
}

void SCLSetVideoDataSettings(AVCaptureVideoDataOutput *output, NSDictionary<NSString *, id> *settings) {
    objc_setAssociatedObject(output, SCLVideoSettingsKey, [settings copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

NSDictionary<NSString *, id> *SCLVideoDataSettings(AVCaptureVideoDataOutput *output) {
    NSDictionary *settings = objc_getAssociatedObject(output, SCLVideoSettingsKey);
    if (settings[(id)kCVPixelBufferPixelFormatTypeKey]) {
        return settings;
    }
    NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:settings ?: @{}];
    merged[(id)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange);
    return merged;
}

static CGSize SCLPresetSize(AVCaptureSessionPreset preset) {
    if (!preset || [preset isEqualToString:AVCaptureSessionPresetHigh] || [preset isEqualToString:AVCaptureSessionPreset1920x1080]
        || [preset isEqualToString:AVCaptureSessionPreset3840x2160]) {
        return CGSizeMake(1920, 1080);
    }
    if ([preset isEqualToString:AVCaptureSessionPresetPhoto] || [preset isEqualToString:AVCaptureSessionPresetInputPriority]) {
        return CGSizeMake(SCL_SENSOR_WIDTH, SCL_SENSOR_HEIGHT);
    }
    if ([preset isEqualToString:AVCaptureSessionPreset1280x720] || [preset isEqualToString:AVCaptureSessionPresetiFrame1280x720]) {
        return CGSizeMake(1280, 720);
    }
    if ([preset isEqualToString:AVCaptureSessionPresetiFrame960x540]) {
        return CGSizeMake(960, 540);
    }
    if ([preset isEqualToString:AVCaptureSessionPreset640x480]) {
        return CGSizeMake(640, 480);
    }
    if ([preset isEqualToString:AVCaptureSessionPresetMedium]) {
        return CGSizeMake(480, 360);
    }
    if ([preset isEqualToString:AVCaptureSessionPreset352x288]) {
        return CGSizeMake(352, 288);
    }
    if ([preset isEqualToString:AVCaptureSessionPresetLow]) {
        return CGSizeMake(192, 144);
    }
    return CGSizeMake(1920, 1080);
}

static CGImagePropertyOrientation SCLOrientationForAngle(CGFloat angle) {
    int quarter = ((int)lround(angle / 90.0) % 4 + 4) % 4;
    switch (quarter) {
        case 1: return kCGImagePropertyOrientationRight;
        case 2: return kCGImagePropertyOrientationDown;
        case 3: return kCGImagePropertyOrientationLeft;
        default: return kCGImagePropertyOrientationUp;
    }
}

static CIImage *SCLNormalized(CIImage *image) {
    CGRect extent = image.extent;
    return [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x, -extent.origin.y)];
}

static CIImage *SCLOriented(CIImage *image, CGFloat angle, BOOL mirrored) {
    CIImage *result = [image imageByApplyingCGOrientation:SCLOrientationForAngle(angle)];
    if (mirrored) {
        result = [result imageByApplyingCGOrientation:kCGImagePropertyOrientationUpMirrored];
    }
    return SCLNormalized(result);
}

@interface SCLOutputContext : NSObject
@property (nonatomic) CVPixelBufferPoolRef pool;
@property (nonatomic) OSType format;
@property (nonatomic) size_t width;
@property (nonatomic) size_t height;
@property (atomic) BOOL inFlight;
@end

@implementation SCLOutputContext

- (void)dealloc {
    if (_pool) {
        CVPixelBufferPoolRelease(_pool);
    }
}

- (CVPixelBufferRef)makeBufferWithFormat:(OSType)format width:(size_t)width height:(size_t)height CF_RETURNS_RETAINED {
    if (!_pool || _format != format || _width != width || _height != height) {
        if (_pool) {
            CVPixelBufferPoolRelease(_pool);
            _pool = NULL;
        }
        NSDictionary *attributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(format),
            (id)kCVPixelBufferWidthKey: @(width),
            (id)kCVPixelBufferHeightKey: @(height),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
            (id)kCVPixelBufferMetalCompatibilityKey: @YES,
        };
        CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attributes, &_pool);
        _format = format;
        _width = width;
        _height = height;
    }
    CVPixelBufferRef buffer = NULL;
    if (_pool) {
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pool, &buffer);
    }
    return buffer;
}

@end

@implementation SCLFramePump {
    dispatch_queue_t _queue;
    dispatch_queue_t _photoQueue;
    dispatch_source_t _timer;
    CIContext *_context;
    CGColorSpaceRef _colorSpace;
    CIImage *_placeholder;
    uint64_t _lastTickNs;
}

+ (instancetype)shared {
    static SCLFramePump *pump;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pump = [SCLFramePump new];
    });
    return pump;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("dev.ifateam.simcamlite.pump", DISPATCH_QUEUE_SERIAL);
        _photoQueue = dispatch_queue_create("dev.ifateam.simcamlite.photo", DISPATCH_QUEUE_SERIAL);
        _colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        _context = [CIContext contextWithOptions:@{
            kCIContextWorkingColorSpace: (__bridge id)_colorSpace,
            kCIContextCacheIntermediates: @NO,
        }];
    }
    return self;
}

#pragma mark Lifecycle

- (void)sessionStatesDidChange {
    dispatch_async(_queue, ^{
        BOOL anyRunning = SCLRunningSessionStates().count > 0;
        if (anyRunning && !self->_timer) {
            self->_lastTickNs = SCLNowNs();
            self->_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self->_queue);
            uint64_t interval = (uint64_t)(NSEC_PER_SEC / SCLPollRate);
            dispatch_source_set_timer(self->_timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, interval / 10);
            __weak SCLFramePump *weakSelf = self;
            dispatch_source_set_event_handler(self->_timer, ^{
                [weakSelf tick];
            });
            dispatch_resume(self->_timer);
            SCLLogInfo("Frame pump started");
        } else if (!anyRunning && self->_timer) {
            dispatch_source_cancel(self->_timer);
            self->_timer = nil;
            [SCLFrameReader.shared reportCameraState:SCLClientCameraIdle width:0 height:0];
            SCLLogInfo("Frame pump stopped");
        }
    });
}

- (void)tick {
    uint64_t now = SCLNowNs();
    NSTimeInterval interval = (now - _lastTickNs) / 1e9;
    _lastTickNs = now;

    for (SCLSessionState *state in SCLRunningSessionStates()) {
        AVCaptureSession *session = state.session;
        SCLFakeDevice *device = state.activeDevice;
        if (!session || !device) {
            continue;
        }
        [device sclStepRampWithInterval:interval];
        uint64_t counter = [SCLFrameReader.shared frameCounterForStream:device.sclStream];
        BOOL fresh = counter != 0 ? counter != state.lastFrameCounter : now - state.lastDeliveryNs >= NSEC_PER_SEC / SCLFrameRate;
        if (!fresh && device == state.lastDevice) {
            continue;
        }
        state.lastFrameCounter = counter;
        state.lastDeliveryNs = now;
        state.lastDevice = device;
        CGSize size = SCLPresetSize(state.preset);
        CIImage *sensor = [self sensorImageForDevice:device size:size];
        state.latestSensorImage = sensor;

        for (AVCaptureOutput *output in state.managedOutputs) {
            if ([output isKindOfClass:AVCaptureVideoDataOutput.class]) {
                [self deliverImage:sensor toOutput:(AVCaptureVideoDataOutput *)output session:session device:device];
            }
        }
        for (AVCaptureVideoPreviewLayer *layer in state.previewLayers) {
            [self renderImage:sensor toPreviewLayer:layer session:session device:device];
        }
        [SCLFrameReader.shared reportCameraState:(device.position == AVCaptureDevicePositionFront ? SCLClientCameraFront : SCLClientCameraBack)
                                           width:(uint32_t)size.width
                                          height:(uint32_t)size.height];
    }
}

#pragma mark Sensor image

- (CIImage *)placeholder {
    if (_placeholder) {
        return _placeholder;
    }
    CGSize portrait = CGSizeMake(SCL_SENSOR_HEIGHT, SCL_SENSOR_WIDTH);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:portrait format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor colorWithWhite:0.12 alpha:1] setFill];
        [context fillRect:CGRectMake(0, 0, portrait.width, portrait.height)];
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.alignment = NSTextAlignmentCenter;
        NSDictionary *title = @{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:96],
            NSForegroundColorAttributeName: UIColor.whiteColor,
            NSParagraphStyleAttributeName: style,
        };
        NSDictionary *body = @{
            NSFontAttributeName: [UIFont systemFontOfSize:56],
            NSForegroundColorAttributeName: [UIColor colorWithWhite:0.75 alpha:1],
            NSParagraphStyleAttributeName: style,
        };
        [@"SimCamLite" drawInRect:CGRectMake(0, 760, portrait.width, 130) withAttributes:title];
        [@"Host app is not running.\nOpen SimCamLite on Mac." drawInRect:CGRectMake(0, 920, portrait.width, 200) withAttributes:body];
    }];
    CIImage *ciImage = [CIImage imageWithCGImage:image.CGImage];
    _placeholder = SCLNormalized([ciImage imageByApplyingCGOrientation:kCGImagePropertyOrientationLeft]);
    return _placeholder;
}

- (CIImage *)sensorImageForDevice:(SCLFakeDevice *)device size:(CGSize)size {
    CVPixelBufferRef frame = [SCLFrameReader.shared copyFrameForStream:device.sclStream];
    CIImage *base = frame ? [CIImage imageWithCVPixelBuffer:frame] : [self placeholder];
    if (frame) {
        CVPixelBufferRelease(frame);
    }
    CGRect extent = base.extent;
    CGFloat aspect = size.width / size.height;
    CGRect crop = extent;
    if (extent.size.width / extent.size.height > aspect) {
        crop.size.width = extent.size.height * aspect;
        crop.origin.x += (extent.size.width - crop.size.width) / 2;
    } else {
        crop.size.height = extent.size.width / aspect;
        crop.origin.y += (extent.size.height - crop.size.height) / 2;
    }
    CGFloat zoom = device.sclFrameCrop;
    if (zoom > 1) {
        crop = CGRectInset(crop, crop.size.width * (1 - 1 / zoom) / 2, crop.size.height * (1 - 1 / zoom) / 2);
    }
    CGFloat scale = size.width / crop.size.width;
    CIImage *image = [base imageByCroppingToRect:crop];
    image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-crop.origin.x, -crop.origin.y)];
    image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
    image = [image imageByCroppingToRect:CGRectMake(0, 0, size.width, size.height)];

    float bias = device.sclExposureBias;
    if (fabsf(bias) > 0.01f) {
        image = [[image imageByApplyingFilter:@"CIExposureAdjust" withInputParameters:@{kCIInputEVKey: @(bias)}]
                 imageByCroppingToRect:CGRectMake(0, 0, size.width, size.height)];
    }
    return image;
}

#pragma mark Video data output

- (void)deliverImage:(CIImage *)sensor toOutput:(AVCaptureVideoDataOutput *)output session:(AVCaptureSession *)session device:(SCLFakeDevice *)device {
    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = SCLVideoDataDelegate(output);
    dispatch_queue_t queue = SCLVideoDataQueue(output);
    if (!delegate || !queue) {
        return;
    }
    SCLOutputContext *context = objc_getAssociatedObject(output, SCLOutputContextKey);
    if (!context) {
        context = [SCLOutputContext new];
        objc_setAssociatedObject(output, SCLOutputContextKey, context, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (context.inFlight && output.alwaysDiscardsLateVideoFrames) {
        return;
    }

    SCLFakeConnection *connection = SCLConnectionForOutput(output, session);
    if (!connection.isEnabled) {
        return;
    }
    CIImage *image = SCLOriented(sensor, connection.videoRotationAngle, [connection sclEffectiveMirroredForDevice:device]);

    NSDictionary *settings = SCLVideoDataSettings(output);
    OSType format = [settings[(id)kCVPixelBufferPixelFormatTypeKey] unsignedIntValue];
    if (format != kCVPixelFormatType_32BGRA && format != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        && format != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
        format = kCVPixelFormatType_32BGRA;
    }
    size_t width = (size_t)image.extent.size.width;
    size_t height = (size_t)image.extent.size.height;
    NSNumber *requestedWidth = settings[(id)kCVPixelBufferWidthKey];
    NSNumber *requestedHeight = settings[(id)kCVPixelBufferHeightKey];
    if (requestedWidth.unsignedIntegerValue > 0 && requestedHeight.unsignedIntegerValue > 0) {
        width = requestedWidth.unsignedIntegerValue;
        height = requestedHeight.unsignedIntegerValue;
        image = [image imageByApplyingTransform:CGAffineTransformMakeScale(width / image.extent.size.width, height / image.extent.size.height)];
    }

    CVPixelBufferRef buffer = [context makeBufferWithFormat:format width:width height:height];
    if (!buffer) {
        return;
    }
    [_context render:image toCVPixelBuffer:buffer bounds:CGRectMake(0, 0, width, height) colorSpace:_colorSpace];

    CMVideoFormatDescriptionRef formatDescription = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, buffer, &formatDescription);
    CMSampleTimingInfo timing = {
        .duration = CMTimeMake(1, (int32_t)SCLFrameRate),
        .presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock()),
        .decodeTimeStamp = kCMTimeInvalid,
    };
    CMSampleBufferRef sampleBuffer = NULL;
    if (formatDescription) {
        CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, buffer, formatDescription, &timing, &sampleBuffer);
        CFRelease(formatDescription);
    }
    CVPixelBufferRelease(buffer);
    if (!sampleBuffer) {
        return;
    }

    context.inFlight = YES;
    dispatch_async(queue, ^{
        if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            [delegate captureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
        }
        CFRelease(sampleBuffer);
        context.inFlight = NO;
        [SCLFrameReader.shared reportFrameDelivered];
    });
}

#pragma mark Preview layer

static CALayerContentsGravity SCLGravity(AVLayerVideoGravity gravity) {
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        return kCAGravityResizeAspectFill;
    }
    if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        return kCAGravityResize;
    }
    return kCAGravityResizeAspect;
}

- (void)renderImage:(CIImage *)sensor toPreviewLayer:(AVCaptureVideoPreviewLayer *)layer session:(AVCaptureSession *)session device:(SCLFakeDevice *)device {
    NSNumber *busy = objc_getAssociatedObject(layer, SCLPreviewBusyKey);
    if (busy.boolValue) {
        return;
    }
    SCLFakeConnection *connection = SCLConnectionForPreviewLayer(layer, session);
    if (!connection.isEnabled) {
        return;
    }
    CIImage *image = SCLOriented(sensor, connection.videoRotationAngle, [connection sclEffectiveMirroredForDevice:device]);
    CGFloat longEdge = MAX(image.extent.size.width, image.extent.size.height);
    if (longEdge > SCLPreviewMaxEdge) {
        CGFloat scale = SCLPreviewMaxEdge / longEdge;
        image = SCLNormalized([image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)]);
    }
    SCLOutputContext *context = objc_getAssociatedObject(layer, SCLOutputContextKey);
    if (!context) {
        context = [SCLOutputContext new];
        objc_setAssociatedObject(layer, SCLOutputContextKey, context, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    size_t width = (size_t)lround(image.extent.size.width);
    size_t height = (size_t)lround(image.extent.size.height);
    CVPixelBufferRef buffer = [context makeBufferWithFormat:kCVPixelFormatType_32BGRA width:width height:height];
    if (!buffer) {
        return;
    }
    [_context render:image toCVPixelBuffer:buffer bounds:CGRectMake(0, 0, width, height) colorSpace:_colorSpace];
    objc_setAssociatedObject(layer, SCLPreviewBusyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id frame = CFBridgingRelease(buffer);
    __weak AVCaptureVideoPreviewLayer *weakLayer = layer;
    dispatch_async(dispatch_get_main_queue(), ^{
        AVCaptureVideoPreviewLayer *strongLayer = weakLayer;
        if (!strongLayer) {
            return;
        }
        CALayer *content = objc_getAssociatedObject(strongLayer, SCLPreviewContentKey);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (!content) {
            content = [CALayer layer];
            content.name = @"SimCamLite";
            content.masksToBounds = YES;
            objc_setAssociatedObject(strongLayer, SCLPreviewContentKey, content, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (content.superlayer != strongLayer) {
            [strongLayer insertSublayer:content atIndex:0];
        }
        content.frame = strongLayer.bounds;
        content.contentsGravity = SCLGravity(strongLayer.videoGravity);
        content.contents = (__bridge id)CVPixelBufferGetIOSurface((__bridge CVPixelBufferRef)frame);
        objc_setAssociatedObject(content, SCLPreviewFrameKey, frame, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [CATransaction commit];
        objc_setAssociatedObject(strongLayer, SCLPreviewBusyKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

#pragma mark Photo

static NSString *SCLExifDate(NSDate *date) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy:MM:dd HH:mm:ss";
    return [formatter stringFromDate:date];
}

static int SCLExifOrientation(CGFloat angle) {
    int quarter = ((int)lround(angle / 90.0) % 4 + 4) % 4;
    switch (quarter) {
        case 1: return 6;
        case 2: return 3;
        case 3: return 8;
        default: return 1;
    }
}

- (void)capturePhotoWithOutput:(AVCapturePhotoOutput *)output
                      settings:(AVCapturePhotoSettings *)settings
                      delegate:(id<AVCapturePhotoCaptureDelegate>)delegate
                       session:(AVCaptureSession *)session
                 maxDimensions:(CMVideoDimensions)maxDimensions {
    int64_t uniqueID = settings.uniqueID;
    AVCaptureFlashMode flashMode = settings.flashMode;
    CMVideoDimensions requested = settings.maxPhotoDimensions;
    if (requested.width <= 0 || requested.height <= 0) {
        requested = maxDimensions;
    }

    dispatch_async(_photoQueue, ^{
        SCLSessionState *state = SCLStateForSession(session, NO);
        SCLFakeDevice *device = state.activeDevice;
        CGSize presetSize = SCLPresetSize(state.preset);
        int32_t longEdge = MAX(requested.width, requested.height);
        if (longEdge <= 0) {
            longEdge = 4032;
        }
        longEdge = MIN(longEdge, 4032);
        CGFloat aspect = presetSize.width / presetSize.height;
        CGSize photoSize = CGSizeMake(longEdge, round(longEdge / aspect));

        SCLFakeResolvedPhotoSettings *resolved = [[SCLFakeResolvedPhotoSettings alloc]
            sclInitWithUniqueID:uniqueID
                     dimensions:(CMVideoDimensions){ (int32_t)photoSize.width, (int32_t)photoSize.height }
                   flashEnabled:(flashMode == AVCaptureFlashModeOn && device.hasFlash)];

        if ([delegate respondsToSelector:@selector(captureOutput:willBeginCaptureForResolvedSettings:)]) {
            [delegate captureOutput:output willBeginCaptureForResolvedSettings:resolved];
        }
        if ([delegate respondsToSelector:@selector(captureOutput:willCapturePhotoForResolvedSettings:)]) {
            [delegate captureOutput:output willCapturePhotoForResolvedSettings:resolved];
        }
        if ([delegate respondsToSelector:@selector(captureOutput:didCapturePhotoForResolvedSettings:)]) {
            [delegate captureOutput:output didCapturePhotoForResolvedSettings:resolved];
        }

        NSError *error = nil;
        SCLFakePhoto *photo = nil;
        if (device) {
            photo = [self makePhotoWithDevice:device output:output session:session size:photoSize resolved:resolved flash:resolved.isFlashEnabled];
        }
        if (!photo) {
            error = [NSError errorWithDomain:AVFoundationErrorDomain code:AVErrorUnknown userInfo:@{
                NSLocalizedDescriptionKey: @"SimCamLite could not produce a photo.",
            }];
        }
        if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
            [delegate captureOutput:output didFinishProcessingPhoto:photo error:error];
        }
        if ([delegate respondsToSelector:@selector(captureOutput:didFinishCaptureForResolvedSettings:error:)]) {
            [delegate captureOutput:output didFinishCaptureForResolvedSettings:resolved error:error];
        }
        if (photo) {
            [SCLFrameReader.shared reportPhotoCaptured];
        }
    });
}

- (SCLFakePhoto *)makePhotoWithDevice:(SCLFakeDevice *)device
                               output:(AVCapturePhotoOutput *)output
                              session:(AVCaptureSession *)session
                                 size:(CGSize)size
                             resolved:(AVCaptureResolvedPhotoSettings *)resolved
                                flash:(BOOL)flash {
    SCLFakeConnection *connection = SCLConnectionForOutput(output, session);
    CIImage *image = [self sensorImageForDevice:device size:size];
    if ([connection sclEffectiveMirroredForDevice:device]) {
        image = SCLNormalized([image imageByApplyingCGOrientation:kCGImagePropertyOrientationUpMirrored]);
    }
    CGImageRef cgImage = [_context createCGImage:image fromRect:image.extent format:kCIFormatRGBA8 colorSpace:_colorSpace];
    if (!cgImage) {
        return nil;
    }

    int orientation = SCLExifOrientation(connection.videoRotationAngle);
    NSDate *now = [NSDate date];
    NSString *date = SCLExifDate(now);
    NSString *model = NSProcessInfo.processInfo.environment[@"SIMULATOR_DEVICE_NAME"] ?: @"SimCamLite";
    double focal = device.sclFocalLength;
    NSDictionary *exif = @{
        (id)kCGImagePropertyExifExposureTime: @(1.0 / 60.0),
        (id)kCGImagePropertyExifFNumber: @(device.lensAperture),
        (id)kCGImagePropertyExifISOSpeedRatings: @[@100],
        (id)kCGImagePropertyExifFocalLength: @(focal),
        (id)kCGImagePropertyExifFocalLenIn35mmFilm: @((int)lround(focal * 3.5)),
        (id)kCGImagePropertyExifLensMake: @"Apple",
        (id)kCGImagePropertyExifLensModel: device.sclLensModel,
        (id)kCGImagePropertyExifExposureBiasValue: @(device.sclExposureBias),
        (id)kCGImagePropertyExifFlash: @(flash ? 1 : 16),
        (id)kCGImagePropertyExifDateTimeOriginal: date,
        (id)kCGImagePropertyExifDateTimeDigitized: date,
        (id)kCGImagePropertyExifPixelXDimension: @(CGImageGetWidth(cgImage)),
        (id)kCGImagePropertyExifPixelYDimension: @(CGImageGetHeight(cgImage)),
    };
    NSDictionary *tiff = @{
        (id)kCGImagePropertyTIFFMake: @"Apple",
        (id)kCGImagePropertyTIFFModel: model,
        (id)kCGImagePropertyTIFFSoftware: @"SimCamLite",
        (id)kCGImagePropertyTIFFOrientation: @(orientation),
        (id)kCGImagePropertyTIFFDateTime: date,
    };
    NSDictionary *metadata = @{
        (id)kCGImagePropertyOrientation: @(orientation),
        (id)kCGImagePropertyExifDictionary: exif,
        (id)kCGImagePropertyTIFFDictionary: tiff,
    };

    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.jpeg"), 1, NULL);
    if (!destination) {
        CGImageRelease(cgImage);
        return nil;
    }
    NSMutableDictionary *properties = [metadata mutableCopy];
    properties[(id)kCGImageDestinationLossyCompressionQuality] = @0.9;
    CGImageDestinationAddImage(destination, cgImage, (__bridge CFDictionaryRef)properties);
    BOOL finalized = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    if (!finalized) {
        CGImageRelease(cgImage);
        return nil;
    }

    SCLFakePhoto *photo = [[SCLFakePhoto alloc] sclInitWithData:data
                                                        cgImage:cgImage
                                                       metadata:metadata
                                               resolvedSettings:resolved
                                                      timestamp:CMClockGetTime(CMClockGetHostTimeClock())
                                                     deviceType:device.deviceType];
    CGImageRelease(cgImage);
    return photo;
}

@end
