#import "SCLFakes.h"
#import "SCLRuntime.h"
#import "SCLSessionState.h"
#import "SCLSharedMemory.h"
#import <UIKit/UIKit.h>

static NSValue *SCLDimensionsValue(int32_t width, int32_t height) {
    CMVideoDimensions dimensions = { width, height };
    return [NSValue valueWithBytes:&dimensions objCType:@encode(CMVideoDimensions)];
}

#pragma mark - Frame rate range

@implementation SCLFakeFrameRateRange

- (instancetype)sclInit __attribute__((objc_method_family(init))) {
    return self;
}

- (Float64)minFrameRate { return 1; }
- (Float64)maxFrameRate { return 60; }
- (CMTime)minFrameDuration { return CMTimeMake(1, 60); }
- (CMTime)maxFrameDuration { return CMTimeMake(1, 1); }
- (NSString *)description { return @"<SCLFakeFrameRateRange 1-60>"; }

@end

#pragma mark - Format

@implementation SCLFakeFormat {
    CGFloat _maxZoom;
    CMVideoFormatDescriptionRef _formatDescription;
    NSArray<AVFrameRateRange *> *_ranges;
}

- (instancetype)sclInitWithMaxZoom:(CGFloat)maxZoom {
    _maxZoom = maxZoom;
    CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                   SCL_SENSOR_WIDTH, SCL_SENSOR_HEIGHT, NULL, &_formatDescription);
    _ranges = @[[[SCLFakeFrameRateRange alloc] sclInit]];
    return self;
}

- (id)figCaptureSourceVideoFormat { return nil; }
- (AVMediaType)mediaType { return AVMediaTypeVideo; }
- (CMFormatDescriptionRef)formatDescription { return _formatDescription; }
- (NSArray<AVFrameRateRange *> *)videoSupportedFrameRateRanges { return _ranges; }
- (float)videoFieldOfView { return 70; }
- (float)geometricDistortionCorrectedVideoFieldOfView { return 70; }
- (BOOL)isVideoBinned { return NO; }
- (BOOL)isVideoStabilizationModeSupported:(AVCaptureVideoStabilizationMode)mode { return mode == AVCaptureVideoStabilizationModeOff; }
- (BOOL)isVideoHDRSupported { return NO; }
- (CMVideoDimensions)highResolutionStillImageDimensions { return (CMVideoDimensions){ 4032, 3024 }; }
- (NSArray<NSValue *> *)supportedMaxPhotoDimensions { return @[SCLDimensionsValue(1920, 1440), SCLDimensionsValue(4032, 3024)]; }
- (CGFloat)videoMaxZoomFactor { return _maxZoom; }
- (CGFloat)videoZoomFactorUpscaleThreshold { return 1; }
- (CMTime)minExposureDuration { return CMTimeMake(1, 10000); }
- (CMTime)maxExposureDuration { return CMTimeMake(1, 1); }
- (float)minISO { return 25; }
- (float)maxISO { return 3200; }
- (BOOL)isGlobalToneMappingSupported { return NO; }
- (NSArray<NSNumber *> *)supportedColorSpaces { return @[@(AVCaptureColorSpace_sRGB)]; }
- (NSArray<AVCaptureDeviceFormat *> *)supportedDepthDataFormats { return @[]; }
- (NSArray<Class> *)unsupportedCaptureOutputClasses { return @[]; }
- (AVCaptureAutoFocusSystem)autoFocusSystem { return AVCaptureAutoFocusSystemPhaseDetection; }
- (BOOL)isMultiCamSupported { return NO; }
- (BOOL)isHighestPhotoQualitySupported { return YES; }
- (BOOL)isHighPhotoQualitySupported { return YES; }
- (BOOL)isPortraitEffectsMatteStillImageDeliverySupported { return NO; }
- (NSArray<NSNumber *> *)secondaryNativeResolutionZoomFactors { return @[]; }
- (BOOL)isCenterStageSupported { return NO; }
- (BOOL)isPortraitEffectSupported { return NO; }
- (BOOL)isStudioLightSupported { return NO; }
- (BOOL)isAutoVideoFrameRateSupported { return NO; }
- (BOOL)isBackgroundReplacementSupported { return NO; }
- (BOOL)reactionEffectsSupported { return NO; }
- (BOOL)isSpatialVideoCaptureSupported { return NO; }
- (CGFloat)videoMinZoomFactorForDepthDataDelivery { return 1; }
- (CGFloat)videoMaxZoomFactorForDepthDataDelivery { return _maxZoom; }
- (NSArray *)supportedVideoZoomFactorsForDepthDataDelivery { return @[]; }
- (NSArray *)supportedVideoZoomRangesForDepthDataDelivery { return @[]; }
- (NSString *)description { return @"<SCLFakeFormat 1920x1440 420f>"; }

@end

#pragma mark - Device

@implementation SCLFakeDevice {
    AVCaptureDeviceType _type;
    AVCaptureDevicePosition _position;
    NSString *_uniqueID;
    NSString *_name;
    CGFloat _baseCrop;
    CGFloat _maxZoom;
    NSArray<NSNumber *> *_switchOver;
    NSArray<AVCaptureDevice *> *_constituents;
    CGFloat _displayMultiplier;
    SCLFakeFormat *_format;
    SCLFakeDeviceInput *_input;

    CGFloat _zoom;
    CGFloat _rampTarget;
    float _rampRate;
    BOOL _ramping;
    AVCaptureFocusMode _focusMode;
    CGPoint _focusPoint;
    AVCaptureExposureMode _exposureMode;
    CGPoint _exposurePoint;
    float _bias;
    AVCaptureWhiteBalanceMode _whiteBalanceMode;
    AVCaptureTorchMode _torchMode;
    AVCaptureFlashMode _flashMode;
    CMTime _minFrameDuration;
    CMTime _maxFrameDuration;
    BOOL _subjectAreaMonitoring;
    BOOL _smoothAutoFocus;
    AVCaptureAutoFocusRangeRestriction _rangeRestriction;
}

- (instancetype)sclInitWithType:(AVCaptureDeviceType)type
                       position:(AVCaptureDevicePosition)position
                       uniqueID:(NSString *)uniqueID
                           name:(NSString *)name
                       baseCrop:(CGFloat)baseCrop
                        maxZoom:(CGFloat)maxZoom
                     switchOver:(NSArray<NSNumber *> *)switchOver
                   constituents:(NSArray<AVCaptureDevice *> *)constituents
              displayMultiplier:(CGFloat)displayMultiplier {
    _type = type;
    _position = position;
    _uniqueID = [uniqueID copy];
    _name = [name copy];
    _baseCrop = baseCrop;
    _maxZoom = maxZoom;
    _switchOver = [switchOver copy];
    _constituents = [constituents copy];
    _displayMultiplier = displayMultiplier;
    _format = [[SCLFakeFormat alloc] sclInitWithMaxZoom:maxZoom];
    _zoom = 1;
    _rampTarget = 1;
    _focusMode = AVCaptureFocusModeContinuousAutoFocus;
    _focusPoint = CGPointMake(0.5, 0.5);
    _exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    _exposurePoint = CGPointMake(0.5, 0.5);
    _whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
    _minFrameDuration = CMTimeMake(1, 30);
    _maxFrameDuration = CMTimeMake(1, 30);
    _input = [[SCLFakeDeviceInput alloc] sclInitWithDevice:self];
    return self;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key { return YES; }

- (BOOL)isEqual:(id)object { return self == object; }
- (NSUInteger)hash { return (NSUInteger)(__bridge void *)self; }
- (NSString *)description { return [NSString stringWithFormat:@"<SCLFakeDevice %@ %@>", _name, _uniqueID]; }
- (NSString *)debugDescription { return self.description; }

- (int)sclStream { return _position == AVCaptureDevicePositionFront ? SCLStreamFront : SCLStreamBack; }
- (SCLFakeDeviceInput *)sclInput { return _input; }

- (CGFloat)sclSensorCrop {
    @synchronized (self) {
        return MAX(1, _zoom * _baseCrop);
    }
}

- (float)sclExposureBias {
    @synchronized (self) {
        return _bias;
    }
}

- (double)sclFocalLength {
    if (_position == AVCaptureDevicePositionFront) {
        return 2.69;
    }
    CGFloat crop = self.sclSensorCrop;
    if (_switchOver.count >= 2 && crop >= _switchOver[1].doubleValue) {
        return 9.0;
    }
    if ((_switchOver.count >= 1 || [_type isEqualToString:AVCaptureDeviceTypeBuiltInUltraWideCamera]) && crop < 2) {
        return [_type isEqualToString:AVCaptureDeviceTypeBuiltInWideAngleCamera] ? 6.86 : 2.22;
    }
    return 6.86;
}

- (NSString *)sclLensModel {
    if (_position == AVCaptureDevicePositionFront) {
        return @"SimCamLite front camera 2.69mm f/1.9";
    }
    double focal = self.sclFocalLength;
    NSString *aperture = focal < 3 ? @"f/2.2" : (focal > 8 ? @"f/2.8" : @"f/1.78");
    return [NSString stringWithFormat:@"SimCamLite back camera %.2fmm %@", focal, aperture];
}

- (void)sclStepRampWithInterval:(NSTimeInterval)interval {
    BOOL changed = NO;
    CGFloat next = 0;
    @synchronized (self) {
        if (!_ramping) {
            return;
        }
        double step = pow(2.0, _rampRate * interval);
        next = _zoom < _rampTarget ? MIN(_rampTarget, _zoom * step) : MAX(_rampTarget, _zoom / step);
        changed = YES;
    }
    if (changed) {
        [self willChangeValueForKey:@"videoZoomFactor"];
        @synchronized (self) {
            _zoom = next;
            if (fabs(_zoom - _rampTarget) < 0.0001) {
                _ramping = NO;
            }
        }
        [self didChangeValueForKey:@"videoZoomFactor"];
    }
}

#pragma mark Identity

- (NSString *)uniqueID { return _uniqueID; }
- (NSString *)modelID { return @"SimCamLite"; }
- (NSString *)localizedName { return _name; }
- (NSString *)manufacturer { return @"Apple Inc."; }
- (AVCaptureDeviceType)deviceType { return _type; }
- (AVCaptureDevicePosition)position { return _position; }
- (int32_t)transportType { return 0; }
- (BOOL)isConnected { return YES; }
- (BOOL)isSuspended { return NO; }
- (NSArray<AVCaptureDevice *> *)linkedDevices { return @[]; }
- (BOOL)hasMediaType:(AVMediaType)mediaType { return [mediaType isEqualToString:AVMediaTypeVideo]; }
- (BOOL)supportsAVCaptureSessionPreset:(AVCaptureSessionPreset)preset { return YES; }
- (BOOL)isContinuityCamera { return NO; }
- (AVCaptureDevice *)companionDeskViewCamera { return nil; }

#pragma mark Formats

- (NSArray<AVCaptureDeviceFormat *> *)formats { return @[_format]; }
- (AVCaptureDeviceFormat *)activeFormat { return _format; }
- (void)setActiveFormat:(AVCaptureDeviceFormat *)activeFormat {}
- (CMTime)activeVideoMinFrameDuration { return _minFrameDuration; }
- (void)setActiveVideoMinFrameDuration:(CMTime)duration { _minFrameDuration = duration; }
- (CMTime)activeVideoMaxFrameDuration { return _maxFrameDuration; }
- (void)setActiveVideoMaxFrameDuration:(CMTime)duration { _maxFrameDuration = duration; }
- (AVCaptureDeviceFormat *)activeDepthDataFormat { return nil; }
- (void)setActiveDepthDataFormat:(AVCaptureDeviceFormat *)format {}
- (AVCaptureColorSpace)activeColorSpace { return AVCaptureColorSpace_sRGB; }
- (void)setActiveColorSpace:(AVCaptureColorSpace)colorSpace {}

#pragma mark Configuration

- (BOOL)lockForConfiguration:(NSError **)outError { return YES; }
- (void)unlockForConfiguration {}

#pragma mark Virtual device

- (BOOL)isVirtualDevice { return _constituents.count > 0; }
- (NSArray<AVCaptureDevice *> *)constituentDevices { return _constituents; }
- (NSArray<NSNumber *> *)virtualDeviceSwitchOverVideoZoomFactors { return _switchOver; }
- (CGFloat)dualCameraSwitchOverVideoZoomFactor { return _switchOver.firstObject ? _switchOver.firstObject.doubleValue : 1; }
- (AVCapturePrimaryConstituentDeviceSwitchingBehavior)primaryConstituentDeviceSwitchingBehavior { return AVCapturePrimaryConstituentDeviceSwitchingBehaviorAuto; }
- (AVCapturePrimaryConstituentDeviceSwitchingBehavior)activePrimaryConstituentDeviceSwitchingBehavior { return AVCapturePrimaryConstituentDeviceSwitchingBehaviorAuto; }
- (AVCapturePrimaryConstituentDeviceRestrictedSwitchingBehaviorConditions)primaryConstituentDeviceRestrictedSwitchingBehaviorConditions { return 0; }
- (AVCapturePrimaryConstituentDeviceRestrictedSwitchingBehaviorConditions)activePrimaryConstituentDeviceRestrictedSwitchingBehaviorConditions { return 0; }
- (void)setPrimaryConstituentDeviceSwitchingBehavior:(AVCapturePrimaryConstituentDeviceSwitchingBehavior)behavior restrictedSwitchingBehaviorConditions:(AVCapturePrimaryConstituentDeviceRestrictedSwitchingBehaviorConditions)conditions {}
- (AVCaptureDevice *)activePrimaryConstituentDevice { return nil; }
- (NSArray<AVCaptureDevice *> *)supportedFallbackPrimaryConstituentDevices { return @[]; }
- (NSArray<AVCaptureDevice *> *)fallbackPrimaryConstituentDevices { return @[]; }
- (void)setFallbackPrimaryConstituentDevices:(NSArray<AVCaptureDevice *> *)devices {}

#pragma mark Zoom

- (CGFloat)videoZoomFactor {
    @synchronized (self) {
        return _zoom;
    }
}

- (void)setVideoZoomFactor:(CGFloat)factor {
    @synchronized (self) {
        _zoom = MIN(MAX(1, factor), _maxZoom);
        _rampTarget = _zoom;
        _ramping = NO;
    }
}

- (CGFloat)minAvailableVideoZoomFactor { return 1; }
- (CGFloat)maxAvailableVideoZoomFactor { return _maxZoom; }
- (CGFloat)displayVideoZoomFactorMultiplier { return _displayMultiplier; }

- (void)rampToVideoZoomFactor:(CGFloat)factor withRate:(float)rate {
    [self willChangeValueForKey:@"rampingVideoZoom"];
    @synchronized (self) {
        _rampTarget = MIN(MAX(1, factor), _maxZoom);
        _rampRate = MAX(0.1f, fabsf(rate));
        _ramping = YES;
    }
    [self didChangeValueForKey:@"rampingVideoZoom"];
}

- (void)cancelVideoZoomRamp {
    @synchronized (self) {
        _ramping = NO;
        _rampTarget = _zoom;
    }
}

- (BOOL)isRampingVideoZoom {
    @synchronized (self) {
        return _ramping;
    }
}

#pragma mark Focus

- (BOOL)isFocusModeSupported:(AVCaptureFocusMode)mode { return _position == AVCaptureDevicePositionBack; }
- (AVCaptureFocusMode)focusMode { return _focusMode; }
- (void)setFocusMode:(AVCaptureFocusMode)mode { _focusMode = mode; }
- (BOOL)isFocusPointOfInterestSupported { return _position == AVCaptureDevicePositionBack; }
- (CGPoint)focusPointOfInterest { return _focusPoint; }
- (void)setFocusPointOfInterest:(CGPoint)point { _focusPoint = point; }
- (BOOL)isAdjustingFocus { return NO; }
- (float)lensPosition { return 0.5f; }
- (BOOL)isLockingFocusWithCustomLensPositionSupported { return YES; }
- (void)setFocusModeLockedWithLensPosition:(float)lensPosition completionHandler:(void (^)(CMTime))handler {
    _focusMode = AVCaptureFocusModeLocked;
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{ handler(CMClockGetTime(CMClockGetHostTimeClock())); });
    }
}
- (BOOL)isAutoFocusRangeRestrictionSupported { return YES; }
- (AVCaptureAutoFocusRangeRestriction)autoFocusRangeRestriction { return _rangeRestriction; }
- (void)setAutoFocusRangeRestriction:(AVCaptureAutoFocusRangeRestriction)restriction { _rangeRestriction = restriction; }
- (BOOL)isSmoothAutoFocusSupported { return YES; }
- (BOOL)isSmoothAutoFocusEnabled { return _smoothAutoFocus; }
- (void)setSmoothAutoFocusEnabled:(BOOL)enabled { _smoothAutoFocus = enabled; }
- (BOOL)automaticallyAdjustsFaceDrivenAutoFocusEnabled { return YES; }
- (void)setAutomaticallyAdjustsFaceDrivenAutoFocusEnabled:(BOOL)enabled {}
- (BOOL)isFaceDrivenAutoFocusEnabled { return NO; }
- (void)setFaceDrivenAutoFocusEnabled:(BOOL)enabled {}
- (NSInteger)minimumFocusDistance { return 20; }
- (BOOL)isSubjectAreaChangeMonitoringEnabled { return _subjectAreaMonitoring; }
- (void)setSubjectAreaChangeMonitoringEnabled:(BOOL)enabled { _subjectAreaMonitoring = enabled; }

#pragma mark Exposure

- (BOOL)isExposureModeSupported:(AVCaptureExposureMode)mode { return YES; }
- (AVCaptureExposureMode)exposureMode { return _exposureMode; }
- (void)setExposureMode:(AVCaptureExposureMode)mode { _exposureMode = mode; }
- (BOOL)isExposurePointOfInterestSupported { return YES; }
- (CGPoint)exposurePointOfInterest { return _exposurePoint; }
- (void)setExposurePointOfInterest:(CGPoint)point { _exposurePoint = point; }
- (BOOL)automaticallyAdjustsFaceDrivenAutoExposureEnabled { return YES; }
- (void)setAutomaticallyAdjustsFaceDrivenAutoExposureEnabled:(BOOL)enabled {}
- (BOOL)isFaceDrivenAutoExposureEnabled { return NO; }
- (void)setFaceDrivenAutoExposureEnabled:(BOOL)enabled {}
- (CMTime)activeMaxExposureDuration { return CMTimeMake(1, 3); }
- (void)setActiveMaxExposureDuration:(CMTime)duration {}
- (BOOL)isAdjustingExposure { return NO; }
- (float)lensAperture { return _position == AVCaptureDevicePositionFront ? 1.9f : 1.78f; }
- (CMTime)exposureDuration { return CMTimeMake(1, 60); }
- (float)ISO { return 100; }
- (float)exposureTargetOffset { return 0; }
- (float)minExposureTargetBias { return -8; }
- (float)maxExposureTargetBias { return 8; }

- (float)exposureTargetBias {
    @synchronized (self) {
        return _bias;
    }
}

- (void)setExposureTargetBias:(float)bias completionHandler:(void (^)(CMTime))handler {
    [self willChangeValueForKey:@"exposureTargetBias"];
    @synchronized (self) {
        _bias = MIN(MAX(bias, -8), 8);
    }
    [self didChangeValueForKey:@"exposureTargetBias"];
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{ handler(CMClockGetTime(CMClockGetHostTimeClock())); });
    }
}

- (void)setExposureModeCustomWithDuration:(CMTime)duration ISO:(float)ISO completionHandler:(void (^)(CMTime))handler {
    _exposureMode = AVCaptureExposureModeCustom;
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{ handler(CMClockGetTime(CMClockGetHostTimeClock())); });
    }
}

- (BOOL)isGlobalToneMappingEnabled { return NO; }
- (void)setGlobalToneMappingEnabled:(BOOL)enabled {}

#pragma mark White balance

- (BOOL)isWhiteBalanceModeSupported:(AVCaptureWhiteBalanceMode)mode { return YES; }
- (AVCaptureWhiteBalanceMode)whiteBalanceMode { return _whiteBalanceMode; }
- (void)setWhiteBalanceMode:(AVCaptureWhiteBalanceMode)mode { _whiteBalanceMode = mode; }
- (BOOL)isAdjustingWhiteBalance { return NO; }
- (BOOL)isLockingWhiteBalanceWithCustomDeviceGainsSupported { return YES; }
- (AVCaptureWhiteBalanceGains)deviceWhiteBalanceGains { return (AVCaptureWhiteBalanceGains){ 1, 1, 1 }; }
- (AVCaptureWhiteBalanceGains)grayWorldDeviceWhiteBalanceGains { return (AVCaptureWhiteBalanceGains){ 1, 1, 1 }; }
- (float)maxWhiteBalanceGain { return 4; }
- (void)setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains completionHandler:(void (^)(CMTime))handler {
    _whiteBalanceMode = AVCaptureWhiteBalanceModeLocked;
    if (handler) {
        dispatch_async(dispatch_get_main_queue(), ^{ handler(CMClockGetTime(CMClockGetHostTimeClock())); });
    }
}
- (AVCaptureWhiteBalanceChromaticityValues)chromaticityValuesForDeviceWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains { return (AVCaptureWhiteBalanceChromaticityValues){ 0.3127f, 0.329f }; }
- (AVCaptureWhiteBalanceGains)deviceWhiteBalanceGainsForChromaticityValues:(AVCaptureWhiteBalanceChromaticityValues)values { return (AVCaptureWhiteBalanceGains){ 1, 1, 1 }; }
- (AVCaptureWhiteBalanceTemperatureAndTintValues)temperatureAndTintValuesForDeviceWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains { return (AVCaptureWhiteBalanceTemperatureAndTintValues){ 5500, 0 }; }
- (AVCaptureWhiteBalanceGains)deviceWhiteBalanceGainsForTemperatureAndTintValues:(AVCaptureWhiteBalanceTemperatureAndTintValues)values { return (AVCaptureWhiteBalanceGains){ 1, 1, 1 }; }

#pragma mark Flash & torch

- (BOOL)hasFlash { return _position == AVCaptureDevicePositionBack; }
- (BOOL)isFlashAvailable { return self.hasFlash; }
- (BOOL)isFlashActive { return NO; }
- (BOOL)isFlashModeSupported:(AVCaptureFlashMode)mode { return self.hasFlash || mode == AVCaptureFlashModeOff; }
- (AVCaptureFlashMode)flashMode { return _flashMode; }
- (void)setFlashMode:(AVCaptureFlashMode)mode { _flashMode = mode; }
- (BOOL)hasTorch { return _position == AVCaptureDevicePositionBack; }
- (BOOL)isTorchAvailable { return self.hasTorch; }
- (BOOL)isTorchActive { return _torchMode == AVCaptureTorchModeOn; }
- (float)torchLevel { return _torchMode == AVCaptureTorchModeOn ? 1 : 0; }
- (BOOL)isTorchModeSupported:(AVCaptureTorchMode)mode { return self.hasTorch || mode == AVCaptureTorchModeOff; }
- (AVCaptureTorchMode)torchMode { return _torchMode; }
- (void)setTorchMode:(AVCaptureTorchMode)mode { _torchMode = mode; }
- (BOOL)setTorchModeOnWithLevel:(float)level error:(NSError **)outError {
    _torchMode = AVCaptureTorchModeOn;
    return YES;
}

#pragma mark Misc

- (BOOL)isLowLightBoostSupported { return NO; }
- (BOOL)isLowLightBoostEnabled { return NO; }
- (BOOL)automaticallyEnablesLowLightBoostWhenAvailable { return NO; }
- (void)setAutomaticallyEnablesLowLightBoostWhenAvailable:(BOOL)enabled {}
- (BOOL)isVideoHDREnabled { return NO; }
- (void)setVideoHDREnabled:(BOOL)enabled {}
- (BOOL)automaticallyAdjustsVideoHDREnabled { return YES; }
- (void)setAutomaticallyAdjustsVideoHDREnabled:(BOOL)enabled {}
- (BOOL)isGeometricDistortionCorrectionSupported { return NO; }
- (BOOL)isGeometricDistortionCorrectionEnabled { return NO; }
- (void)setGeometricDistortionCorrectionEnabled:(BOOL)enabled {}
- (BOOL)isCenterStageActive { return NO; }
- (BOOL)isPortraitEffectActive { return NO; }
- (BOOL)isStudioLightActive { return NO; }
- (BOOL)isBackgroundReplacementActive { return NO; }
- (BOOL)canPerformReactionEffects { return NO; }
- (NSSet *)availableReactionTypes { return [NSSet set]; }
- (NSArray *)reactionEffectsInProgress { return @[]; }
- (BOOL)isVideoStabilizationModeSupported:(AVCaptureVideoStabilizationMode)mode { return mode == AVCaptureVideoStabilizationModeOff; }

@end

#pragma mark - Input port

@implementation SCLFakeInputPort {
    __weak AVCaptureInput *_input;
    __weak SCLFakeDevice *_device;
    BOOL _enabled;
}

- (instancetype)sclInitWithInput:(AVCaptureInput *)input device:(SCLFakeDevice *)device {
    _input = input;
    _device = device;
    _enabled = YES;
    return self;
}

- (AVCaptureInput *)input { return _input; }
- (AVMediaType)mediaType { return AVMediaTypeVideo; }
- (CMFormatDescriptionRef)formatDescription { return _device.activeFormat.formatDescription; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; }
- (CMClockRef)clock { return CMClockGetHostTimeClock(); }
- (AVCaptureDeviceType)sourceDeviceType { return _device.deviceType; }
- (AVCaptureDevicePosition)sourceDevicePosition { return _device.position; }
- (NSString *)description { return @"<SCLFakeInputPort video>"; }

@end

#pragma mark - Device input

@implementation SCLFakeDeviceInput {
    __weak SCLFakeDevice *_device;
    NSArray<AVCaptureInputPort *> *_ports;
    BOOL _unifiedAutoExposureDefaults;
    CMTime _minFrameDurationOverride;
}

- (instancetype)sclInitWithDevice:(SCLFakeDevice *)device {
    _device = device;
    _ports = @[[[SCLFakeInputPort alloc] sclInitWithInput:self device:device]];
    _unifiedAutoExposureDefaults = YES;
    _minFrameDurationOverride = kCMTimeInvalid;
    return self;
}

- (BOOL)isEqual:(id)object { return self == object; }
- (NSUInteger)hash { return (NSUInteger)(__bridge void *)self; }
- (NSString *)description { return [NSString stringWithFormat:@"<SCLFakeDeviceInput %@>", _device.localizedName]; }
- (AVCaptureDevice *)device { return _device; }
- (NSArray<AVCaptureInputPort *> *)ports { return _ports; }
- (NSArray<AVCaptureInputPort *> *)portsWithMediaType:(AVMediaType)mediaType sourceDeviceType:(AVCaptureDeviceType)sourceDeviceType sourceDevicePosition:(AVCaptureDevicePosition)sourceDevicePosition {
    return [mediaType isEqualToString:AVMediaTypeVideo] ? _ports : @[];
}
- (BOOL)unifiedAutoExposureDefaultsEnabled { return _unifiedAutoExposureDefaults; }
- (void)setUnifiedAutoExposureDefaultsEnabled:(BOOL)enabled { _unifiedAutoExposureDefaults = enabled; }
- (CMTime)videoMinFrameDurationOverride { return _minFrameDurationOverride; }
- (void)setVideoMinFrameDurationOverride:(CMTime)duration { _minFrameDurationOverride = duration; }
- (BOOL)isWindNoiseRemovalSupported { return NO; }

@end

#pragma mark - Connection

@implementation SCLFakeConnection {
    SCLConnectionKind _kind;
    __weak AVCaptureOutput *_output;
    __weak AVCaptureVideoPreviewLayer *_previewLayer;
    __weak AVCaptureSession *_session;
    BOOL _enabled;
    CGFloat _angle;
    BOOL _autoMirroring;
    BOOL _mirrored;
    CGFloat _scaleAndCrop;
    AVCaptureVideoStabilizationMode _stabilization;
    BOOL _intrinsicDelivery;
}

- (instancetype)sclInitWithKind:(SCLConnectionKind)kind output:(AVCaptureOutput *)output previewLayer:(AVCaptureVideoPreviewLayer *)previewLayer session:(AVCaptureSession *)session {
    _kind = kind;
    _output = output;
    _previewLayer = previewLayer;
    _session = session;
    _enabled = YES;
    _angle = kind == SCLConnectionKindPreview ? 90 : 0;
    _autoMirroring = YES;
    _scaleAndCrop = 1;
    _stabilization = AVCaptureVideoStabilizationModeOff;
    return self;
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key { return YES; }

- (BOOL)isEqual:(id)object { return self == object; }
- (NSUInteger)hash { return (NSUInteger)(__bridge void *)self; }
- (NSString *)description { return [NSString stringWithFormat:@"<SCLFakeConnection kind=%ld angle=%.0f>", (long)_kind, _angle]; }

- (SCLConnectionKind)sclKind { return _kind; }
- (AVCaptureSession *)sclSession { return _session; }

- (BOOL)sclEffectiveMirroredForDevice:(SCLFakeDevice *)device {
    @synchronized (self) {
        if (_autoMirroring) {
            return _kind == SCLConnectionKindPreview && device.position == AVCaptureDevicePositionFront;
        }
        return _mirrored;
    }
}

- (NSArray<AVCaptureInputPort *> *)inputPorts {
    AVCaptureSession *session = _session;
    SCLFakeDevice *device = session ? SCLStateForSession(session, NO).activeDevice : nil;
    return device ? device.sclInput.ports : @[];
}

- (AVCaptureOutput *)output { return _output; }
- (AVCaptureVideoPreviewLayer *)videoPreviewLayer { return _previewLayer; }
- (BOOL)isEnabled { return _enabled; }
- (void)setEnabled:(BOOL)enabled { _enabled = enabled; }
- (BOOL)isActive { return YES; }
- (NSArray<AVCaptureAudioChannel *> *)audioChannels { return @[]; }

- (BOOL)isVideoRotationAngleSupported:(CGFloat)angle {
    double normalized = fmod(angle, 360);
    return fmod(normalized, 90) == 0;
}

- (CGFloat)videoRotationAngle {
    @synchronized (self) {
        return _angle;
    }
}

- (void)setVideoRotationAngle:(CGFloat)angle {
    @synchronized (self) {
        double normalized = fmod(fmod(angle, 360) + 360, 360);
        _angle = round(normalized / 90) * 90;
        if (_angle >= 360) {
            _angle = 0;
        }
    }
}

- (BOOL)isVideoOrientationSupported { return YES; }

- (AVCaptureVideoOrientation)videoOrientation {
    CGFloat angle = self.videoRotationAngle;
    if (angle == 90) return AVCaptureVideoOrientationPortrait;
    if (angle == 180) return AVCaptureVideoOrientationLandscapeLeft;
    if (angle == 270) return AVCaptureVideoOrientationPortraitUpsideDown;
    return AVCaptureVideoOrientationLandscapeRight;
}

- (void)setVideoOrientation:(AVCaptureVideoOrientation)orientation {
    switch (orientation) {
        case AVCaptureVideoOrientationPortrait: self.videoRotationAngle = 90; break;
        case AVCaptureVideoOrientationPortraitUpsideDown: self.videoRotationAngle = 270; break;
        case AVCaptureVideoOrientationLandscapeLeft: self.videoRotationAngle = 180; break;
        case AVCaptureVideoOrientationLandscapeRight: self.videoRotationAngle = 0; break;
    }
}

- (BOOL)isVideoMirroringSupported { return YES; }

- (BOOL)automaticallyAdjustsVideoMirroring {
    @synchronized (self) {
        return _autoMirroring;
    }
}

- (void)setAutomaticallyAdjustsVideoMirroring:(BOOL)value {
    @synchronized (self) {
        _autoMirroring = value;
    }
}

- (BOOL)isVideoMirrored {
    AVCaptureSession *session = _session;
    SCLFakeDevice *device = session ? SCLStateForSession(session, NO).activeDevice : nil;
    return [self sclEffectiveMirroredForDevice:device];
}

- (void)setVideoMirrored:(BOOL)mirrored {
    @synchronized (self) {
        _autoMirroring = NO;
        _mirrored = mirrored;
    }
}

- (CMTime)videoMinFrameDuration { return CMTimeMake(1, 30); }
- (void)setVideoMinFrameDuration:(CMTime)duration {}
- (CMTime)videoMaxFrameDuration { return CMTimeMake(1, 30); }
- (void)setVideoMaxFrameDuration:(CMTime)duration {}
- (BOOL)isVideoMinFrameDurationSupported { return NO; }
- (BOOL)isVideoMaxFrameDurationSupported { return NO; }
- (CGFloat)videoMaxScaleAndCropFactor { return 1; }
- (CGFloat)videoScaleAndCropFactor { return _scaleAndCrop; }
- (void)setVideoScaleAndCropFactor:(CGFloat)factor { _scaleAndCrop = factor; }
- (AVCaptureVideoStabilizationMode)preferredVideoStabilizationMode { return _stabilization; }
- (void)setPreferredVideoStabilizationMode:(AVCaptureVideoStabilizationMode)mode { _stabilization = mode; }
- (AVCaptureVideoStabilizationMode)activeVideoStabilizationMode { return AVCaptureVideoStabilizationModeOff; }
- (BOOL)isVideoStabilizationSupported { return NO; }
- (BOOL)isVideoStabilizationEnabled { return NO; }
- (BOOL)enablesVideoStabilizationWhenAvailable { return NO; }
- (void)setEnablesVideoStabilizationWhenAvailable:(BOOL)value {}
- (BOOL)isCameraIntrinsicMatrixDeliverySupported { return NO; }
- (BOOL)isCameraIntrinsicMatrixDeliveryEnabled { return _intrinsicDelivery; }
- (void)setCameraIntrinsicMatrixDeliveryEnabled:(BOOL)enabled { _intrinsicDelivery = enabled; }
- (BOOL)isVideoFieldModeSupported { return NO; }

@end

#pragma mark - Rotation coordinator

static CGFloat SCLCaptureAngle(UIDeviceOrientation orientation, BOOL front, CGFloat fallback) {
    switch (orientation) {
        case UIDeviceOrientationPortrait: return 90;
        case UIDeviceOrientationPortraitUpsideDown: return 270;
        case UIDeviceOrientationLandscapeLeft: return front ? 180 : 0;
        case UIDeviceOrientationLandscapeRight: return front ? 0 : 180;
        default: return fallback;
    }
}

static CGFloat SCLPreviewAngle(UIInterfaceOrientation orientation, BOOL front) {
    switch (orientation) {
        case UIInterfaceOrientationPortraitUpsideDown: return 270;
        case UIInterfaceOrientationLandscapeRight: return front ? 180 : 0;
        case UIInterfaceOrientationLandscapeLeft: return front ? 0 : 180;
        default: return 90;
    }
}

@implementation SCLFakeRotationCoordinator {
    __weak SCLFakeDevice *_device;
    __weak CALayer *_previewLayer;
    CGFloat _previewAngle;
    CGFloat _captureAngle;
    id _observer;
}

- (instancetype)sclInitWithDevice:(SCLFakeDevice *)device previewLayer:(CALayer *)previewLayer {
    _device = device;
    _previewLayer = previewLayer;
    _previewAngle = 90;
    _captureAngle = 90;
    __weak SCLFakeRotationCoordinator *weakSelf = self;
    dispatch_block_t setup = ^{
        SCLFakeRotationCoordinator *coordinator = weakSelf;
        if (!coordinator) {
            return;
        }
        [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
        coordinator->_observer = [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification
                                                                                  object:nil
                                                                                   queue:NSOperationQueue.mainQueue
                                                                              usingBlock:^(NSNotification *note) {
            [weakSelf sclRefresh];
        }];
        [coordinator sclRefresh];
    };
    if (NSThread.isMainThread) {
        setup();
    } else {
        dispatch_async(dispatch_get_main_queue(), setup);
    }
    return self;
}

- (void)sclRefresh {
    BOOL front = _device.position == AVCaptureDevicePositionFront;
    UIInterfaceOrientation interfaceOrientation = UIInterfaceOrientationPortrait;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            interfaceOrientation = ((UIWindowScene *)scene).interfaceOrientation;
#pragma clang diagnostic pop
            break;
        }
    }
    CGFloat preview = SCLPreviewAngle(interfaceOrientation, front);
    CGFloat capture = SCLCaptureAngle(UIDevice.currentDevice.orientation, front, _captureAngle);
    if (preview != _previewAngle) {
        [self willChangeValueForKey:@"videoRotationAngleForHorizonLevelPreview"];
        _previewAngle = preview;
        [self didChangeValueForKey:@"videoRotationAngleForHorizonLevelPreview"];
    }
    if (capture != _captureAngle) {
        [self willChangeValueForKey:@"videoRotationAngleForHorizonLevelCapture"];
        _captureAngle = capture;
        [self didChangeValueForKey:@"videoRotationAngleForHorizonLevelCapture"];
    }
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key { return NO; }

- (AVCaptureDevice *)device { return _device; }
- (CALayer *)previewLayer { return _previewLayer; }
- (CGFloat)videoRotationAngleForHorizonLevelPreview { return _previewAngle; }
- (CGFloat)videoRotationAngleForHorizonLevelCapture { return _captureAngle; }
- (NSString *)description { return @"<SCLFakeRotationCoordinator>"; }

@end

#pragma mark - Resolved photo settings

@implementation SCLFakeResolvedPhotoSettings {
    int64_t _uniqueID;
    CMVideoDimensions _dimensions;
    BOOL _flashEnabled;
}

- (instancetype)sclInitWithUniqueID:(int64_t)uniqueID dimensions:(CMVideoDimensions)dimensions flashEnabled:(BOOL)flashEnabled {
    _uniqueID = uniqueID;
    _dimensions = dimensions;
    _flashEnabled = flashEnabled;
    return self;
}

- (int64_t)uniqueID { return _uniqueID; }
- (CMVideoDimensions)photoDimensions { return _dimensions; }
- (CMVideoDimensions)rawPhotoDimensions { return (CMVideoDimensions){ 0, 0 }; }
- (CMVideoDimensions)previewDimensions { return (CMVideoDimensions){ 0, 0 }; }
- (CMVideoDimensions)embeddedThumbnailDimensions { return (CMVideoDimensions){ 0, 0 }; }
- (CMVideoDimensions)rawEmbeddedThumbnailDimensions { return (CMVideoDimensions){ 0, 0 }; }
- (CMVideoDimensions)portraitEffectsMatteDimensions { return (CMVideoDimensions){ 0, 0 }; }
- (CMVideoDimensions)livePhotoMovieDimensions { return (CMVideoDimensions){ 0, 0 }; }
- (CMVideoDimensions)deferredPhotoProxyDimensions { return (CMVideoDimensions){ 0, 0 }; }
- (CMVideoDimensions)dimensionsForSemanticSegmentationMatteOfType:(AVSemanticSegmentationMatteType)type { return (CMVideoDimensions){ 0, 0 }; }
- (BOOL)isFlashEnabled { return _flashEnabled; }
- (BOOL)isRedEyeReductionEnabled { return NO; }
- (BOOL)isStillImageStabilizationEnabled { return NO; }
- (BOOL)isVirtualDeviceFusionEnabled { return NO; }
- (BOOL)isDualCameraFusionEnabled { return NO; }
- (BOOL)isContentAwareDistortionCorrectionEnabled { return NO; }
- (BOOL)isFastCapturePrioritizationEnabled { return NO; }
- (NSUInteger)expectedPhotoCount { return 1; }
- (CMTimeRange)photoProcessingTimeRange { return CMTimeRangeMake(kCMTimeZero, CMTimeMake(1, 10)); }
- (NSString *)description { return [NSString stringWithFormat:@"<SCLFakeResolvedPhotoSettings %lld %dx%d>", _uniqueID, _dimensions.width, _dimensions.height]; }

@end

#pragma mark - Photo

@implementation SCLFakePhoto {
    NSData *_data;
    id _cgImage;
    NSDictionary<NSString *, id> *_metadata;
    AVCaptureResolvedPhotoSettings *_resolvedSettings;
    CMTime _timestamp;
    AVCaptureDeviceType _deviceType;
}

- (instancetype)sclInitWithData:(NSData *)data cgImage:(CGImageRef)cgImage metadata:(NSDictionary<NSString *, id> *)metadata resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings timestamp:(CMTime)timestamp deviceType:(AVCaptureDeviceType)deviceType {
    _data = data;
    _cgImage = (__bridge id)cgImage;
    _metadata = [metadata copy];
    _resolvedSettings = resolvedSettings;
    _timestamp = timestamp;
    _deviceType = deviceType;
    return self;
}

- (CMTime)timestamp { return _timestamp; }
- (BOOL)isRawPhoto { return NO; }
- (CVPixelBufferRef)pixelBuffer { return NULL; }
- (CVPixelBufferRef)previewPixelBuffer { return NULL; }
- (NSDictionary *)embeddedThumbnailPhotoFormat { return nil; }
- (AVDepthData *)depthData { return nil; }
- (AVPortraitEffectsMatte *)portraitEffectsMatte { return nil; }
- (AVSemanticSegmentationMatte *)semanticSegmentationMatteForType:(AVSemanticSegmentationMatteType)type { return nil; }
- (NSDictionary<NSString *, id> *)metadata { return _metadata; }
- (AVCameraCalibrationData *)cameraCalibrationData { return nil; }
- (AVCaptureResolvedPhotoSettings *)resolvedSettings { return _resolvedSettings; }
- (NSInteger)photoCount { return 1; }
- (AVCaptureDeviceType)sourceDeviceType { return _deviceType; }
- (AVCaptureBracketedStillImageSettings *)bracketSettings { return nil; }
- (NSInteger)sequenceCount { return 1; }
- (AVCaptureLensStabilizationStatus)lensStabilizationStatus { return AVCaptureLensStabilizationStatusUnsupported; }
- (NSData *)fileDataRepresentation { return _data; }
- (NSData *)fileDataRepresentationWithCustomizer:(id<AVCapturePhotoFileDataRepresentationCustomizer>)customizer { return _data; }
- (CGImageRef)CGImageRepresentation { return (__bridge CGImageRef)_cgImage; }
- (CGImageRef)previewCGImageRepresentation { return NULL; }
- (CVPixelBufferRef)constantColorConfidenceMap { return NULL; }
- (float)constantColorCenterWeightedMeanConfidenceLevel { return 0; }
- (BOOL)isConstantColorFallbackPhoto { return NO; }
- (NSString *)description { return [NSString stringWithFormat:@"<SCLFakePhoto %lu bytes>", (unsigned long)_data.length]; }

@end

void SCLInstallFakeDeallocs(void) {
    SCLInstallSafeDealloc(SCLFakeFrameRateRange.class);
    SCLInstallSafeDealloc(SCLFakeFormat.class);
    SCLInstallSafeDealloc(SCLFakeDevice.class);
    SCLInstallSafeDealloc(SCLFakeInputPort.class);
    SCLInstallSafeDealloc(SCLFakeDeviceInput.class);
    SCLInstallSafeDealloc(SCLFakeConnection.class);
    SCLInstallSafeDealloc(SCLFakeResolvedPhotoSettings.class);
    if (@available(iOS 17.0, *)) {
        SCLInstallSafeDealloc(SCLFakeRotationCoordinator.class);
    }
    SCLInstallSafeDealloc(SCLFakePhoto.class);
}
