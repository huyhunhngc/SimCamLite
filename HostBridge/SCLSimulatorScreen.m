#import "SCLSimulatorScreen.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <xpc/xpc.h>

static NSString *const SCLCoreSimulatorPath = @"/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator";
static NSString *const SCLDigitizerService = @"com.apple.coredevice.feature.remote.hid.digitizer";

typedef xpc_object_t (*SCLEndpointFromPort)(mach_port_t, uint64_t, uint64_t);
typedef xpc_connection_t (*SCLConnectionFromEndpoint)(xpc_object_t);
typedef void (*SCLEnableSim2Host)(xpc_connection_t);

static NSError *SCLError(NSString *message) {
    return [NSError errorWithDomain:@"SimCamLite.SimulatorScreen" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static id SCLSend(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (![target respondsToSelector:sel]) return nil;
    return ((id(*)(id, SEL))objc_msgSend)(target, sel);
}

@implementation SCLSimulatorScreen {
    id _display;
    NSUUID *_token;
    BOOL _usesScreenCallbacks;
    xpc_connection_t _hid;
    dispatch_queue_t _queue;
}

- (nullable instancetype)initWithUDID:(NSString *)udid developerDir:(NSString *)developerDir error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    _token = [NSUUID UUID];
    _queue = dispatch_queue_create("dev.ifateam.simcamlite.simulator-screen", DISPATCH_QUEUE_SERIAL);
    NSString *failure = nil;
    @try {
        id device = [self deviceWithUDID:udid developerDir:developerDir failure:&failure];
        if (device) _display = [self mainDisplayOf:device failure:&failure];
        if (_display) _hid = [self digitizerConnectionFor:device failure:&failure];
        if (_hid) [self registerDisplayCallbacks];
    } @catch (NSException *exception) {
        failure = exception.reason ?: exception.name;
    }
    if (failure) {
        if (error) *error = SCLError(failure);
        return nil;
    }
    return self;
}

- (void)dealloc {
    [self detach];
}

#pragma mark - Device and display

- (nullable id)deviceWithUDID:(NSString *)udid developerDir:(NSString *)developerDir failure:(NSString **)failure {
    if (!dlopen(SCLCoreSimulatorPath.fileSystemRepresentation, RTLD_NOW)) {
        *failure = @"CoreSimulator is not installed.";
        return nil;
    }
    NSError *error = nil;
    Class contextClass = NSClassFromString(@"SimServiceContext");
    SEL contextSel = NSSelectorFromString(@"sharedServiceContextForDeveloperDir:error:");
    if (![contextClass respondsToSelector:contextSel]) {
        *failure = @"This Xcode version is not supported.";
        return nil;
    }
    id context = ((id(*)(id, SEL, id, NSError **))objc_msgSend)(contextClass, contextSel, developerDir, &error);
    id set = context ? ((id(*)(id, SEL, NSError **))objc_msgSend)(context, NSSelectorFromString(@"defaultDeviceSetWithError:"), &error) : nil;
    NSDictionary *devices = SCLSend(set, @"devicesByUDID");
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:udid];
    id device = uuid ? devices[uuid] : nil;
    if (!device) *failure = error.localizedDescription ?: @"Simulator not found.";
    return device;
}

/// The display port whose state says it is the main screen (display class 0).
- (nullable id)mainDisplayOf:(id)device failure:(NSString **)failure {
    Protocol *renderable = objc_getProtocol("SimDisplayIOSurfaceRenderable");
    NSArray *ports = SCLSend(SCLSend(device, @"io"), @"ioPorts");
    for (id port in ports) {
        id descriptor = SCLSend(port, @"descriptor");
        if (!renderable || ![descriptor conformsToProtocol:renderable]) continue;
        id state = SCLSend(descriptor, @"state");
        SEL classSel = NSSelectorFromString(@"displayClass");
        if ([state respondsToSelector:classSel] && ((unsigned short(*)(id, SEL))objc_msgSend)(state, classSel) == 0) {
            return descriptor;
        }
    }
    *failure = @"The simulator screen is not available.";
    return nil;
}

- (nullable IOSurface *)surface {
    id surface = SCLSend(_display, @"framebufferSurface");
    return [surface isKindOfClass:[IOSurface class]] ? surface : nil;
}

- (void)registerDisplayCallbacks {
    __weak typeof(self) weakSelf = self;
    void (^frame)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^onFrame)(void) = weakSelf.onFrame;
            if (onFrame) onFrame();
        });
    };
    void (^surfaceChanged)(id) = ^(id surface) {
        dispatch_async(dispatch_get_main_queue(), ^{
            void (^onSurfaceChange)(IOSurface *) = weakSelf.onSurfaceChange;
            if (onSurfaceChange) onSurfaceChange([surface isKindOfClass:[IOSurface class]] ? surface : nil);
        });
    };
    SEL screenSel = NSSelectorFromString(@"registerScreenCallbacksWithUUID:callbackQueue:frameCallback:surfacesChangedCallback:propertiesChangedCallback:");
    if ([_display respondsToSelector:screenSel]) {
        void (^surfaces)(id, id) = ^(id framebuffer, id masked) { surfaceChanged(framebuffer); };
        void (^properties)(id) = ^(id properties) {};
        ((void(*)(id, SEL, id, id, id, id, id))objc_msgSend)(_display, screenSel, _token, _queue, frame, surfaces, properties);
        _usesScreenCallbacks = YES;
        return;
    }
    ((void(*)(id, SEL, id, id))objc_msgSend)(_display, NSSelectorFromString(@"registerCallbackWithUUID:ioSurfacesChangeCallback:"), _token, surfaceChanged);
    void (^damage)(id) = ^(id rects) { frame(); };
    ((void(*)(id, SEL, id, id))objc_msgSend)(_display, NSSelectorFromString(@"registerCallbackWithUUID:damageRectanglesCallback:"), _token, damage);
}

- (void)unregisterDisplayCallbacks {
    if (!_display) return;
    @try {
        if (_usesScreenCallbacks) {
            ((void(*)(id, SEL, id))objc_msgSend)(_display, NSSelectorFromString(@"unregisterScreenCallbacksWithUUID:"), _token);
        } else {
            for (NSString *selector in @[@"unregisterIOSurfacesChangeCallbackWithUUID:", @"unregisterDamageRectanglesCallbackWithUUID:"]) {
                SEL sel = NSSelectorFromString(selector);
                if ([_display respondsToSelector:sel]) ((void(*)(id, SEL, id))objc_msgSend)(_display, sel, _token);
            }
        }
    } @catch (NSException *exception) {
    }
    _display = nil;
}

#pragma mark - HID

/// Connects to the simulator's `dtuhidd` and waits for its reply, since a send to a daemon that is
/// not running reports no error.
- (nullable xpc_connection_t)digitizerConnectionFor:(id)device failure:(NSString **)failure {
    SCLEndpointFromPort endpointFromPort = dlsym(RTLD_DEFAULT, "xpc_endpoint_create_mach_port_4sim");
    SCLConnectionFromEndpoint connectionFromEndpoint = dlsym(RTLD_DEFAULT, "xpc_connection_create_from_endpoint");
    SCLEnableSim2Host enableSim2Host = dlsym(RTLD_DEFAULT, "xpc_connection_enable_sim2host_4sim");
    SEL lookupSel = NSSelectorFromString(@"lookup:error:");
    if (!endpointFromPort || !connectionFromEndpoint || !enableSim2Host || ![device respondsToSelector:lookupSel]) {
        *failure = @"This Xcode version is not supported.";
        return nil;
    }
    NSError *error = nil;
    mach_port_t port = ((mach_port_t(*)(id, SEL, id, NSError **))objc_msgSend)(device, lookupSel, SCLDigitizerService, &error);
    xpc_object_t endpoint = port ? endpointFromPort(port, 0, 0) : nil;
    xpc_connection_t connection = endpoint ? connectionFromEndpoint(endpoint) : nil;
    if (!connection) {
        *failure = @"Simulator input is not available.";
        return nil;
    }
    enableSim2Host(connection);
    xpc_connection_set_target_queue(connection, _queue);
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {});
    xpc_connection_resume(connection);
    if ([self isAlive:connection]) return connection;
    xpc_connection_cancel(connection);
    *failure = @"Simulator input is not responding.";
    return nil;
}

- (BOOL)isAlive:(xpc_connection_t)connection {
    dispatch_semaphore_t replied = dispatch_semaphore_create(0);
    __block BOOL alive = NO;
    xpc_object_t probe = [self messageOfType:@"IndigoKeyboardButtonEvent" payload:[self keyPayload:0 down:NO] barrier:YES];
    xpc_connection_send_message_with_reply(connection, probe, _queue, ^(xpc_object_t reply) {
        alive = xpc_get_type(reply) != XPC_TYPE_ERROR;
        dispatch_semaphore_signal(replied);
    });
    dispatch_semaphore_wait(replied, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC));
    return alive;
}

- (xpc_object_t)messageOfType:(NSString *)type payload:(xpc_object_t)payload barrier:(BOOL)barrier {
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(message, "messageType", type.UTF8String);
    xpc_dictionary_set_bool(message, "isBarrier", barrier);
    xpc_dictionary_set_string(message, "featureIdentifier", SCLDigitizerService.UTF8String);
    xpc_dictionary_set_value(message, "payload", payload);
    return message;
}

/// `state` is 1-based in `dtuhidd`: 1 down, 2 up.
- (xpc_object_t)keyPayload:(uint64_t)usage down:(BOOL)down {
    xpc_object_t payload = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(payload, "usageCode", usage);
    xpc_dictionary_set_uint64(payload, "state", down ? 1 : 2);
    return payload;
}

- (void)send:(NSString *)type payload:(xpc_object_t)payload {
    xpc_connection_t hid = _hid;
    if (hid) xpc_connection_send_message(hid, [self messageOfType:type payload:payload barrier:NO]);
}

- (void)sendTouch:(SCLTouchPhase)phase x:(double)x y:(double)y edge:(SCLTouchEdge)edge {
    xpc_object_t point = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_double(point, "x", MIN(MAX(x, 0), 1));
    xpc_dictionary_set_double(point, "y", MIN(MAX(y, 0), 1));
    xpc_object_t payload = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_value(payload, "pointOne", point);
    xpc_dictionary_set_uint64(payload, "eventType", phase);
    xpc_dictionary_set_uint64(payload, "edge", edge);
    xpc_dictionary_set_uint64(payload, "target", 0);
    [self send:@"IndigoDigitizerEvent" payload:payload];
}

- (void)sendKey:(uint32_t)usage down:(BOOL)down {
    [self send:@"IndigoKeyboardButtonEvent" payload:[self keyPayload:usage down:down]];
}

- (void)sendButton:(uint16_t)usage down:(BOOL)down {
    xpc_object_t payload = [self keyPayload:usage down:down];
    xpc_dictionary_set_uint64(payload, "usagePage", 0x0C);
    [self send:@"IndigoButtonEvent" payload:payload];
}

- (void)detach {
    [self unregisterDisplayCallbacks];
    if (_hid) xpc_connection_cancel(_hid);
    _hid = nil;
}

@end
