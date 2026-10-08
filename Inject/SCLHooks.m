#import "SCLHooks.h"
#import "SCLFakes.h"
#import "SCLFramePump.h"
#import "SCLRuntime.h"
#import "SCLSessionState.h"
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

static const void *SCLDiscoveryTypesKey = &SCLDiscoveryTypesKey;
static const void *SCLDiscoveryMediaKey = &SCLDiscoveryMediaKey;
static const void *SCLDiscoveryPositionKey = &SCLDiscoveryPositionKey;
static const void *SCLMaxPhotoDimensionsKey = &SCLMaxPhotoDimensionsKey;

static BOOL SCLIsVideoMedia(AVMediaType mediaType) {
    return !mediaType || [mediaType isEqualToString:AVMediaTypeVideo];
}

static BOOL SCLIsFakeInput(id input) {
    return [input isKindOfClass:SCLFakeDeviceInput.class];
}

static __thread int SCLOriginalCallDepth;

#define SCL_ORIGINAL_SCOPE(body) do { SCLOriginalCallDepth++; @try { body; } @finally { SCLOriginalCallDepth--; } } while (0)

static BOOL SCLSessionIsFaked(SCLSessionState *state) {
    return state && (state.fakeInputs.count > 0 || state.managedOutputs.count > 0);
}

#pragma mark - AVCaptureDevice

@implementation AVCaptureDevice (SCLHooks)

+ (AVCaptureDevice *)scl_defaultDeviceWithDeviceType:(AVCaptureDeviceType)type mediaType:(AVMediaType)mediaType position:(AVCaptureDevicePosition)position {
    if (SCLIsVideoMedia(mediaType)) {
        return [SCLDeviceRegistry.shared deviceWithType:type position:position];
    }
    return [self scl_defaultDeviceWithDeviceType:type mediaType:mediaType position:position];
}

+ (AVCaptureDevice *)scl_defaultDeviceWithMediaType:(AVMediaType)mediaType {
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        return SCLDeviceRegistry.shared.defaultBackDevice;
    }
    return [self scl_defaultDeviceWithMediaType:mediaType];
}

+ (AVCaptureDevice *)scl_deviceWithUniqueID:(NSString *)uniqueID {
    return [SCLDeviceRegistry.shared deviceWithUniqueID:uniqueID] ?: [self scl_deviceWithUniqueID:uniqueID];
}

+ (NSArray<AVCaptureDevice *> *)scl_devices {
    return [SCLDeviceRegistry.shared.devices arrayByAddingObjectsFromArray:[self scl_devices]];
}

+ (NSArray<AVCaptureDevice *> *)scl_devicesWithMediaType:(AVMediaType)mediaType {
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        return SCLDeviceRegistry.shared.devices;
    }
    return [self scl_devicesWithMediaType:mediaType];
}

+ (AVAuthorizationStatus)scl_authorizationStatusForMediaType:(AVMediaType)mediaType {
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        return AVAuthorizationStatusAuthorized;
    }
    return [self scl_authorizationStatusForMediaType:mediaType];
}

+ (void)scl_requestAccessForMediaType:(AVMediaType)mediaType completionHandler:(void (^)(BOOL))handler {
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        if (handler) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                handler(YES);
            });
        }
        return;
    }
    [self scl_requestAccessForMediaType:mediaType completionHandler:handler];
}

+ (AVCaptureDevice *)scl_systemPreferredCamera {
    return SCLDeviceRegistry.shared.defaultBackDevice;
}

+ (AVCaptureDevice *)scl_userPreferredCamera {
    return SCLDeviceRegistry.shared.defaultBackDevice;
}

@end

#pragma mark - Discovery session

@implementation AVCaptureDeviceDiscoverySession (SCLHooks)

+ (instancetype)scl_discoverySessionWithDeviceTypes:(NSArray<AVCaptureDeviceType> *)types mediaType:(AVMediaType)mediaType position:(AVCaptureDevicePosition)position {
    AVCaptureDeviceDiscoverySession *session = [self scl_discoverySessionWithDeviceTypes:types mediaType:mediaType position:position];
    if (session) {
        objc_setAssociatedObject(session, SCLDiscoveryTypesKey, [types copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(session, SCLDiscoveryMediaKey, mediaType, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(session, SCLDiscoveryPositionKey, @(position), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return session;
}

- (NSArray<AVCaptureDevice *> *)scl_devices {
    NSArray<AVCaptureDeviceType> *types = objc_getAssociatedObject(self, SCLDiscoveryTypesKey);
    AVMediaType mediaType = objc_getAssociatedObject(self, SCLDiscoveryMediaKey);
    if (!types || !SCLIsVideoMedia(mediaType)) {
        return [self scl_devices];
    }
    AVCaptureDevicePosition position = [objc_getAssociatedObject(self, SCLDiscoveryPositionKey) integerValue];
    return [SCLDeviceRegistry.shared devicesWithTypes:types position:position];
}

- (NSArray<NSSet<AVCaptureDevice *> *> *)scl_supportedMultiCamDeviceSets {
    return @[];
}

@end

#pragma mark - Device input

@interface AVCaptureDeviceInput (SCLHooks)
- (instancetype)scl_initWithDevice:(AVCaptureDevice *)device error:(NSError **)outError __attribute__((objc_method_family(init)));
@end

@implementation AVCaptureDeviceInput (SCLHooks)

- (instancetype)scl_initWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    if ([device isKindOfClass:SCLFakeDevice.class]) {
        SCLLeakObject(self);
        return ((SCLFakeDevice *)device).sclInput;
    }
    return [self scl_initWithDevice:device error:outError];
}

+ (instancetype)scl_deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    if ([device isKindOfClass:SCLFakeDevice.class]) {
        return ((SCLFakeDevice *)device).sclInput;
    }
    return [self scl_deviceInputWithDevice:device error:outError];
}

@end

#pragma mark - Session

@implementation AVCaptureSession (SCLHooks)

- (BOOL)scl_canAddInput:(AVCaptureInput *)input {
    if (SCLIsFakeInput(input)) {
        SCLSessionState *state = SCLStateForSession(self, NO);
        return ![state containsInput:input];
    }
    return [self scl_canAddInput:input];
}

- (void)scl_addInput:(AVCaptureInput *)input {
    if (SCLIsFakeInput(input)) {
        [self willChangeValueForKey:@"inputs"];
        [SCLStateForSession(self, YES) addInput:(SCLFakeDeviceInput *)input];
        [self didChangeValueForKey:@"inputs"];
        SCLLogInfo("Session added %{public}@", ((SCLFakeDeviceInput *)input).device.description);
        return;
    }
    [self scl_addInput:input];
}

- (void)scl_addInputWithNoConnections:(AVCaptureInput *)input {
    if (SCLIsFakeInput(input)) {
        [self addInput:input];
        return;
    }
    [self scl_addInputWithNoConnections:input];
}

- (void)scl_removeInput:(AVCaptureInput *)input {
    if (SCLIsFakeInput(input)) {
        [self willChangeValueForKey:@"inputs"];
        [SCLStateForSession(self, NO) removeInput:input];
        [self didChangeValueForKey:@"inputs"];
        return;
    }
    [self scl_removeInput:input];
}

- (NSArray<AVCaptureInput *> *)scl_inputs {
    NSArray<AVCaptureInput *> *inputs = [self scl_inputs] ?: @[];
    SCLSessionState *state = SCLOriginalCallDepth > 0 ? nil : SCLStateForSession(self, NO);
    return state ? [inputs arrayByAddingObjectsFromArray:state.fakeInputs] : inputs;
}

- (BOOL)scl_canAddOutput:(AVCaptureOutput *)output {
    if (SCLIsManagedOutput(output)) {
        SCLSessionState *state = SCLStateForSession(self, NO);
        return ![state containsOutput:output];
    }
    return [self scl_canAddOutput:output];
}

- (void)scl_addOutput:(AVCaptureOutput *)output {
    if (SCLIsManagedOutput(output)) {
        [self willChangeValueForKey:@"outputs"];
        [SCLStateForSession(self, YES) addOutput:output];
        SCLSetSessionForOutput(output, self);
        [self didChangeValueForKey:@"outputs"];
        SCLLogInfo("Session added %{public}s", class_getName(output.class));
        return;
    }
    [self scl_addOutput:output];
}

- (void)scl_addOutputWithNoConnections:(AVCaptureOutput *)output {
    if (SCLIsManagedOutput(output)) {
        [self addOutput:output];
        return;
    }
    [self scl_addOutputWithNoConnections:output];
}

- (void)scl_removeOutput:(AVCaptureOutput *)output {
    if (SCLIsManagedOutput(output)) {
        [self willChangeValueForKey:@"outputs"];
        [SCLStateForSession(self, NO) removeOutput:output];
        if (SCLSessionForOutput(output) == self) {
            SCLSetSessionForOutput(output, nil);
        }
        [self didChangeValueForKey:@"outputs"];
        return;
    }
    [self scl_removeOutput:output];
}

- (NSArray<AVCaptureOutput *> *)scl_outputs {
    NSArray<AVCaptureOutput *> *outputs = [self scl_outputs] ?: @[];
    SCLSessionState *state = SCLOriginalCallDepth > 0 ? nil : SCLStateForSession(self, NO);
    return state ? [outputs arrayByAddingObjectsFromArray:state.managedOutputs] : outputs;
}

- (void)scl_beginConfiguration {
    SCL_ORIGINAL_SCOPE([self scl_beginConfiguration]);
}

- (void)scl_commitConfiguration {
    SCL_ORIGINAL_SCOPE([self scl_commitConfiguration]);
}

- (void)scl_startRunning {
    SCLSessionState *state = SCLStateForSession(self, NO);
    if (!SCLSessionIsFaked(state)) {
        [self scl_startRunning];
        return;
    }
    if (state.running) {
        return;
    }
    [self willChangeValueForKey:@"running"];
    SCLSetSessionStateRunning(state, YES);
    [self didChangeValueForKey:@"running"];
    [SCLFramePump.shared sessionStatesDidChange];
    [NSNotificationCenter.defaultCenter postNotificationName:AVCaptureSessionDidStartRunningNotification object:self];
    SCLLogInfo("Session started");
}

- (void)scl_stopRunning {
    SCLSessionState *state = SCLStateForSession(self, NO);
    if (!state.running) {
        [self scl_stopRunning];
        return;
    }
    [self willChangeValueForKey:@"running"];
    SCLSetSessionStateRunning(state, NO);
    [self didChangeValueForKey:@"running"];
    [SCLFramePump.shared sessionStatesDidChange];
    [NSNotificationCenter.defaultCenter postNotificationName:AVCaptureSessionDidStopRunningNotification object:self];
    SCLLogInfo("Session stopped");
}

- (BOOL)scl_isRunning {
    SCLSessionState *state = SCLStateForSession(self, NO);
    if (SCLSessionIsFaked(state)) {
        return state.running;
    }
    return [self scl_isRunning];
}

- (BOOL)scl_isInterrupted {
    SCLSessionState *state = SCLStateForSession(self, NO);
    if (SCLSessionIsFaked(state)) {
        return NO;
    }
    return [self scl_isInterrupted];
}

- (BOOL)scl_canSetSessionPreset:(AVCaptureSessionPreset)preset {
    return preset != nil;
}

- (void)scl_setSessionPreset:(AVCaptureSessionPreset)preset {
    SCLStateForSession(self, YES).preset = preset;
    @try {
        SCL_ORIGINAL_SCOPE([self scl_setSessionPreset:preset]);
    } @catch (NSException *exception) {
    }
}

- (AVCaptureSessionPreset)scl_sessionPreset {
    return SCLStateForSession(self, NO).preset ?: [self scl_sessionPreset];
}

@end

#pragma mark - Video data output

@implementation AVCaptureVideoDataOutput (SCLHooks)

- (AVCaptureConnection *)scl_connectionWithMediaType:(AVMediaType)mediaType {
    AVCaptureSession *session = SCLOriginalCallDepth > 0 ? nil : SCLSessionForOutput(self);
    if (session && [mediaType isEqualToString:AVMediaTypeVideo]) {
        return SCLConnectionForOutput(self, session);
    }
    return [self scl_connectionWithMediaType:mediaType];
}

- (NSArray<AVCaptureConnection *> *)scl_connections {
    AVCaptureSession *session = SCLOriginalCallDepth > 0 ? nil : SCLSessionForOutput(self);
    return session ? @[SCLConnectionForOutput(self, session)] : [self scl_connections];
}

- (void)scl_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate queue:(dispatch_queue_t)queue {
    SCLSetVideoDataDelegate(self, delegate, queue);
    @try {
        [self scl_setSampleBufferDelegate:delegate queue:queue];
    } @catch (NSException *exception) {
    }
}

- (void)scl_setVideoSettings:(NSDictionary<NSString *, id> *)settings {
    SCLSetVideoDataSettings(self, settings);
    @try {
        [self scl_setVideoSettings:settings];
    } @catch (NSException *exception) {
    }
}

- (NSDictionary<NSString *, id> *)scl_videoSettings {
    return SCLVideoDataSettings(self);
}

- (NSArray<NSNumber *> *)scl_availableVideoCVPixelFormatTypes {
    return @[@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange), @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange), @(kCVPixelFormatType_32BGRA)];
}

@end

#pragma mark - Photo output

@implementation AVCapturePhotoOutput (SCLHooks)

- (AVCaptureConnection *)scl_connectionWithMediaType:(AVMediaType)mediaType {
    AVCaptureSession *session = SCLOriginalCallDepth > 0 ? nil : SCLSessionForOutput(self);
    if (session && [mediaType isEqualToString:AVMediaTypeVideo]) {
        return SCLConnectionForOutput(self, session);
    }
    return [self scl_connectionWithMediaType:mediaType];
}

- (NSArray<AVCaptureConnection *> *)scl_connections {
    AVCaptureSession *session = SCLOriginalCallDepth > 0 ? nil : SCLSessionForOutput(self);
    return session ? @[SCLConnectionForOutput(self, session)] : [self scl_connections];
}

- (void)scl_capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    AVCaptureSession *session = SCLSessionForOutput(self);
    if (!session || !SCLStateForSession(session, NO).activeDevice) {
        [self scl_capturePhotoWithSettings:settings delegate:delegate];
        return;
    }
    [SCLFramePump.shared capturePhotoWithOutput:self settings:settings delegate:delegate session:session maxDimensions:self.maxPhotoDimensions];
}

- (NSArray<NSNumber *> *)scl_supportedFlashModes {
    AVCaptureSession *session = SCLSessionForOutput(self);
    SCLFakeDevice *device = session ? SCLStateForSession(session, NO).activeDevice : nil;
    if (device && !device.hasFlash) {
        return @[@(AVCaptureFlashModeOff)];
    }
    return @[@(AVCaptureFlashModeOff), @(AVCaptureFlashModeOn), @(AVCaptureFlashModeAuto)];
}

- (NSArray<AVVideoCodecType> *)scl_availablePhotoCodecTypes {
    return @[AVVideoCodecTypeHEVC, AVVideoCodecTypeJPEG];
}

- (NSArray<NSNumber *> *)scl_availablePhotoPixelFormatTypes {
    return @[@(kCVPixelFormatType_32BGRA), @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)];
}

- (NSArray<AVFileType> *)scl_availablePhotoFileTypes {
    return @[AVFileTypeHEIC, AVFileTypeJPEG];
}

- (CMVideoDimensions)scl_maxPhotoDimensions {
    NSValue *value = objc_getAssociatedObject(self, SCLMaxPhotoDimensionsKey);
    CMVideoDimensions dimensions = { 4032, 3024 };
    if (value) {
        [value getValue:&dimensions size:sizeof(dimensions)];
    }
    return dimensions;
}

- (void)scl_setMaxPhotoDimensions:(CMVideoDimensions)dimensions {
    objc_setAssociatedObject(self, SCLMaxPhotoDimensionsKey, [NSValue valueWithBytes:&dimensions objCType:@encode(CMVideoDimensions)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)scl_setMaxPhotoQualityPrioritization:(AVCapturePhotoQualityPrioritization)prioritization {
    @try {
        [self scl_setMaxPhotoQualityPrioritization:prioritization];
    } @catch (NSException *exception) {
    }
}

- (void)scl_setHighResolutionCaptureEnabled:(BOOL)enabled {
    @try {
        [self scl_setHighResolutionCaptureEnabled:enabled];
    } @catch (NSException *exception) {
    }
}

@end

#pragma mark - Preview layer

static CGRect SCLVideoRectInLayer(AVCaptureVideoPreviewLayer *layer, SCLFakeConnection *connection, SCLSessionState *state) {
    CGSize content = state.latestSensorImage ? state.latestSensorImage.extent.size : CGSizeMake(4, 3);
    int quarter = ((int)lround(connection.videoRotationAngle / 90.0) % 4 + 4) % 4;
    if (quarter % 2 == 1) {
        content = CGSizeMake(content.height, content.width);
    }
    CGRect bounds = layer.bounds;
    if ([layer.videoGravity isEqualToString:AVLayerVideoGravityResize] || content.width <= 0 || content.height <= 0) {
        return bounds;
    }
    CGFloat sx = bounds.size.width / content.width;
    CGFloat sy = bounds.size.height / content.height;
    CGFloat scale = [layer.videoGravity isEqualToString:AVLayerVideoGravityResizeAspectFill] ? MAX(sx, sy) : MIN(sx, sy);
    CGSize size = CGSizeMake(content.width * scale, content.height * scale);
    return CGRectMake(CGRectGetMidX(bounds) - size.width / 2, CGRectGetMidY(bounds) - size.height / 2, size.width, size.height);
}

@interface AVCaptureVideoPreviewLayer (SCLHooks)
- (instancetype)scl_initWithSession:(AVCaptureSession *)session __attribute__((objc_method_family(init)));
- (instancetype)scl_initWithSessionWithNoConnection:(AVCaptureSession *)session __attribute__((objc_method_family(init)));
@end

@implementation AVCaptureVideoPreviewLayer (SCLHooks)

- (void)scl_register:(AVCaptureSession *)session {
    if (session) {
        [SCLStateForSession(session, YES) addPreviewLayer:self];
    }
}

- (instancetype)scl_initWithSession:(AVCaptureSession *)session {
    AVCaptureVideoPreviewLayer *layer = [self scl_initWithSession:session];
    [layer scl_register:session];
    return layer;
}

- (instancetype)scl_initWithSessionWithNoConnection:(AVCaptureSession *)session {
    AVCaptureVideoPreviewLayer *layer = [self scl_initWithSessionWithNoConnection:session];
    [layer scl_register:session];
    return layer;
}

- (void)scl_setSession:(AVCaptureSession *)session {
    [self scl_setSession:session];
    [self scl_register:session];
}

- (void)scl_setSessionWithNoConnection:(AVCaptureSession *)session {
    [self scl_setSessionWithNoConnection:session];
    [self scl_register:session];
}

- (SCLSessionState *)scl_fakedState {
    AVCaptureSession *session = self.session;
    SCLSessionState *state = session ? SCLStateForSession(session, NO) : nil;
    return state.fakeInputs.count > 0 ? state : nil;
}

- (AVCaptureConnection *)scl_connection {
    SCLSessionState *state = [self scl_fakedState];
    if (state) {
        return SCLConnectionForPreviewLayer(self, state.session);
    }
    return [self scl_connection];
}

- (CGPoint)scl_captureDevicePointOfInterestForPoint:(CGPoint)point {
    SCLSessionState *state = [self scl_fakedState];
    if (!state) {
        return [self scl_captureDevicePointOfInterestForPoint:point];
    }
    SCLFakeConnection *connection = SCLConnectionForPreviewLayer(self, state.session);
    CGRect rect = SCLVideoRectInLayer(self, connection, state);
    CGFloat u = (point.x - rect.origin.x) / rect.size.width;
    CGFloat v = (point.y - rect.origin.y) / rect.size.height;
    if ([connection sclEffectiveMirroredForDevice:state.activeDevice]) {
        u = 1 - u;
    }
    switch (((int)lround(connection.videoRotationAngle / 90.0) % 4 + 4) % 4) {
        case 1: return CGPointMake(v, 1 - u);
        case 2: return CGPointMake(1 - u, 1 - v);
        case 3: return CGPointMake(1 - v, u);
        default: return CGPointMake(u, v);
    }
}

- (CGPoint)scl_pointForCaptureDevicePointOfInterest:(CGPoint)devicePoint {
    SCLSessionState *state = [self scl_fakedState];
    if (!state) {
        return [self scl_pointForCaptureDevicePointOfInterest:devicePoint];
    }
    SCLFakeConnection *connection = SCLConnectionForPreviewLayer(self, state.session);
    CGRect rect = SCLVideoRectInLayer(self, connection, state);
    CGFloat sx = devicePoint.x;
    CGFloat sy = devicePoint.y;
    CGFloat u = sx;
    CGFloat v = sy;
    switch (((int)lround(connection.videoRotationAngle / 90.0) % 4 + 4) % 4) {
        case 1: u = 1 - sy; v = sx; break;
        case 2: u = 1 - sx; v = 1 - sy; break;
        case 3: u = sy; v = 1 - sx; break;
        default: break;
    }
    if ([connection sclEffectiveMirroredForDevice:state.activeDevice]) {
        u = 1 - u;
    }
    return CGPointMake(rect.origin.x + u * rect.size.width, rect.origin.y + v * rect.size.height);
}

@end

#pragma mark - Rotation coordinator

API_AVAILABLE(ios(17.0))
@interface AVCaptureDeviceRotationCoordinator (SCLHooks)
- (instancetype)scl_initWithDevice:(AVCaptureDevice *)device previewLayer:(CALayer *)previewLayer __attribute__((objc_method_family(init)));
@end

API_AVAILABLE(ios(17.0))
@implementation AVCaptureDeviceRotationCoordinator (SCLHooks)

- (instancetype)scl_initWithDevice:(AVCaptureDevice *)device previewLayer:(CALayer *)previewLayer {
    if ([device isKindOfClass:SCLFakeDevice.class]) {
        SCLLeakObject(self);
        return [[SCLFakeRotationCoordinator alloc] sclInitWithDevice:(SCLFakeDevice *)device previewLayer:previewLayer];
    }
    return [self scl_initWithDevice:device previewLayer:previewLayer];
}

@end

#pragma mark - Install

#define SCL_HOOK_INSTANCE(cls, name) SCLSwizzleInstance(cls, @selector(name), @selector(scl_##name))
#define SCL_HOOK_CLASS(cls, name) SCLSwizzleClass(cls, @selector(name), @selector(scl_##name))

void SCLInstallHooks(void) {
    Class device = AVCaptureDevice.class;
    SCL_HOOK_CLASS(device, defaultDeviceWithDeviceType:mediaType:position:);
    SCL_HOOK_CLASS(device, defaultDeviceWithMediaType:);
    SCL_HOOK_CLASS(device, deviceWithUniqueID:);
    SCL_HOOK_CLASS(device, devices);
    SCL_HOOK_CLASS(device, devicesWithMediaType:);
    SCL_HOOK_CLASS(device, authorizationStatusForMediaType:);
    SCL_HOOK_CLASS(device, requestAccessForMediaType:completionHandler:);
    SCL_HOOK_CLASS(device, systemPreferredCamera);
    SCL_HOOK_CLASS(device, userPreferredCamera);

    Class discovery = AVCaptureDeviceDiscoverySession.class;
    SCL_HOOK_CLASS(discovery, discoverySessionWithDeviceTypes:mediaType:position:);
    SCL_HOOK_INSTANCE(discovery, devices);
    SCL_HOOK_INSTANCE(discovery, supportedMultiCamDeviceSets);

    Class input = AVCaptureDeviceInput.class;
    SCL_HOOK_INSTANCE(input, initWithDevice:error:);
    SCL_HOOK_CLASS(input, deviceInputWithDevice:error:);

    Class session = AVCaptureSession.class;
    SCL_HOOK_INSTANCE(session, canAddInput:);
    SCL_HOOK_INSTANCE(session, addInput:);
    SCL_HOOK_INSTANCE(session, addInputWithNoConnections:);
    SCL_HOOK_INSTANCE(session, removeInput:);
    SCL_HOOK_INSTANCE(session, inputs);
    SCL_HOOK_INSTANCE(session, canAddOutput:);
    SCL_HOOK_INSTANCE(session, addOutput:);
    SCL_HOOK_INSTANCE(session, addOutputWithNoConnections:);
    SCL_HOOK_INSTANCE(session, removeOutput:);
    SCL_HOOK_INSTANCE(session, outputs);
    SCL_HOOK_INSTANCE(session, beginConfiguration);
    SCL_HOOK_INSTANCE(session, commitConfiguration);
    SCL_HOOK_INSTANCE(session, startRunning);
    SCL_HOOK_INSTANCE(session, stopRunning);
    SCL_HOOK_INSTANCE(session, isRunning);
    SCL_HOOK_INSTANCE(session, isInterrupted);
    SCL_HOOK_INSTANCE(session, canSetSessionPreset:);
    SCL_HOOK_INSTANCE(session, setSessionPreset:);
    SCL_HOOK_INSTANCE(session, sessionPreset);

    Class videoData = AVCaptureVideoDataOutput.class;
    SCL_HOOK_INSTANCE(videoData, connectionWithMediaType:);
    SCL_HOOK_INSTANCE(videoData, connections);
    SCL_HOOK_INSTANCE(videoData, setSampleBufferDelegate:queue:);
    SCL_HOOK_INSTANCE(videoData, setVideoSettings:);
    SCL_HOOK_INSTANCE(videoData, videoSettings);
    SCL_HOOK_INSTANCE(videoData, availableVideoCVPixelFormatTypes);

    Class photo = AVCapturePhotoOutput.class;
    SCL_HOOK_INSTANCE(photo, connectionWithMediaType:);
    SCL_HOOK_INSTANCE(photo, connections);
    SCL_HOOK_INSTANCE(photo, capturePhotoWithSettings:delegate:);
    SCL_HOOK_INSTANCE(photo, supportedFlashModes);
    SCL_HOOK_INSTANCE(photo, availablePhotoCodecTypes);
    SCL_HOOK_INSTANCE(photo, availablePhotoPixelFormatTypes);
    SCL_HOOK_INSTANCE(photo, availablePhotoFileTypes);
    SCL_HOOK_INSTANCE(photo, maxPhotoDimensions);
    SCL_HOOK_INSTANCE(photo, setMaxPhotoDimensions:);
    SCL_HOOK_INSTANCE(photo, setMaxPhotoQualityPrioritization:);
    SCL_HOOK_INSTANCE(photo, setHighResolutionCaptureEnabled:);

    Class preview = AVCaptureVideoPreviewLayer.class;
    SCL_HOOK_INSTANCE(preview, initWithSession:);
    SCL_HOOK_INSTANCE(preview, initWithSessionWithNoConnection:);
    SCL_HOOK_INSTANCE(preview, setSession:);
    SCL_HOOK_INSTANCE(preview, setSessionWithNoConnection:);
    SCL_HOOK_INSTANCE(preview, connection);
    SCL_HOOK_INSTANCE(preview, captureDevicePointOfInterestForPoint:);
    SCL_HOOK_INSTANCE(preview, pointForCaptureDevicePointOfInterest:);

    if (@available(iOS 17.0, *)) {
        SCL_HOOK_INSTANCE(AVCaptureDeviceRotationCoordinator.class, initWithDevice:previewLayer:);
    }
    SCLLogInfo("Hooks installed");
}
