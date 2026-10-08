#import "SCLSessionState.h"
#import "SCLFrameReader.h"
#import "SCLRuntime.h"
#import <objc/runtime.h>

static const void *SCLSessionStateKey = &SCLSessionStateKey;
static const void *SCLOutputSessionKey = &SCLOutputSessionKey;
static const void *SCLOutputConnectionKey = &SCLOutputConnectionKey;
static const void *SCLLayerConnectionKey = &SCLLayerConnectionKey;

@implementation SCLSessionState {
    NSMutableArray<SCLFakeDeviceInput *> *_inputs;
    NSMutableArray<AVCaptureOutput *> *_outputs;
    NSHashTable<AVCaptureVideoPreviewLayer *> *_layers;
}

- (instancetype)initWithSession:(AVCaptureSession *)session {
    if ((self = [super init])) {
        _session = session;
        _inputs = [NSMutableArray array];
        _outputs = [NSMutableArray array];
        _layers = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (SCLFakeDevice *)activeDevice {
    @synchronized (self) {
        return (SCLFakeDevice *)_inputs.firstObject.device;
    }
}

- (NSArray<SCLFakeDeviceInput *> *)fakeInputs {
    @synchronized (self) {
        return [_inputs copy];
    }
}

- (NSArray<AVCaptureOutput *> *)managedOutputs {
    @synchronized (self) {
        return [_outputs copy];
    }
}

- (NSArray<AVCaptureVideoPreviewLayer *> *)previewLayers {
    @synchronized (self) {
        return _layers.allObjects;
    }
}

- (BOOL)containsInput:(AVCaptureInput *)input {
    @synchronized (self) {
        return [_inputs indexOfObjectIdenticalTo:(SCLFakeDeviceInput *)input] != NSNotFound;
    }
}

- (void)addInput:(SCLFakeDeviceInput *)input {
    @synchronized (self) {
        if ([_inputs indexOfObjectIdenticalTo:input] == NSNotFound) {
            [_inputs addObject:input];
        }
    }
}

- (void)removeInput:(AVCaptureInput *)input {
    @synchronized (self) {
        [_inputs removeObjectIdenticalTo:(SCLFakeDeviceInput *)input];
    }
}

- (BOOL)containsOutput:(AVCaptureOutput *)output {
    @synchronized (self) {
        return [_outputs indexOfObjectIdenticalTo:output] != NSNotFound;
    }
}

- (void)addOutput:(AVCaptureOutput *)output {
    @synchronized (self) {
        if ([_outputs indexOfObjectIdenticalTo:output] == NSNotFound) {
            [_outputs addObject:output];
        }
    }
}

- (void)removeOutput:(AVCaptureOutput *)output {
    @synchronized (self) {
        [_outputs removeObjectIdenticalTo:output];
    }
}

- (void)addPreviewLayer:(AVCaptureVideoPreviewLayer *)layer {
    @synchronized (self) {
        [_layers addObject:layer];
    }
}

@end

static NSHashTable<SCLSessionState *> *SCLRunningStates(void) {
    static NSHashTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = [NSHashTable weakObjectsHashTable];
    });
    return table;
}

SCLSessionState *SCLStateForSession(AVCaptureSession *session, BOOL create) {
    if (!session) {
        return nil;
    }
    @synchronized (session) {
        SCLSessionState *state = objc_getAssociatedObject(session, SCLSessionStateKey);
        if (!state && create) {
            state = [[SCLSessionState alloc] initWithSession:session];
            objc_setAssociatedObject(session, SCLSessionStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return state;
    }
}

NSArray<SCLSessionState *> *SCLRunningSessionStates(void) {
    NSHashTable *table = SCLRunningStates();
    @synchronized (table) {
        return table.allObjects;
    }
}

void SCLSetSessionStateRunning(SCLSessionState *state, BOOL running) {
    state.running = running;
    NSHashTable *table = SCLRunningStates();
    @synchronized (table) {
        if (running) {
            [table addObject:state];
        } else {
            [table removeObject:state];
        }
    }
}

BOOL SCLIsManagedOutput(AVCaptureOutput *output) {
    return [output isKindOfClass:AVCaptureVideoDataOutput.class] || [output isKindOfClass:AVCapturePhotoOutput.class];
}

AVCaptureSession *SCLSessionForOutput(AVCaptureOutput *output) {
    SCLWeakBox *box = objc_getAssociatedObject(output, SCLOutputSessionKey);
    return box.value;
}

void SCLSetSessionForOutput(AVCaptureOutput *output, AVCaptureSession *session) {
    objc_setAssociatedObject(output, SCLOutputSessionKey, session ? [SCLWeakBox boxWithValue:session] : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

SCLFakeConnection *SCLConnectionForOutput(AVCaptureOutput *output, AVCaptureSession *session) {
    @synchronized (output) {
        SCLFakeConnection *connection = objc_getAssociatedObject(output, SCLOutputConnectionKey);
        if (!connection || connection.sclSession != session) {
            SCLConnectionKind kind = SCLConnectionKindOther;
            if ([output isKindOfClass:AVCaptureVideoDataOutput.class]) {
                kind = SCLConnectionKindVideoData;
            } else if ([output isKindOfClass:AVCapturePhotoOutput.class]) {
                kind = SCLConnectionKindPhoto;
            }
            connection = [[SCLFakeConnection alloc] sclInitWithKind:kind output:output previewLayer:nil session:session];
            objc_setAssociatedObject(output, SCLOutputConnectionKey, connection, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return connection;
    }
}

SCLFakeConnection *SCLConnectionForPreviewLayer(AVCaptureVideoPreviewLayer *layer, AVCaptureSession *session) {
    @synchronized (layer) {
        SCLFakeConnection *connection = objc_getAssociatedObject(layer, SCLLayerConnectionKey);
        if (!connection || connection.sclSession != session) {
            connection = [[SCLFakeConnection alloc] sclInitWithKind:SCLConnectionKindPreview output:nil previewLayer:layer session:session];
            objc_setAssociatedObject(layer, SCLLayerConnectionKey, connection, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return connection;
    }
}

#pragma mark - Device registry

@implementation SCLDeviceRegistry {
    NSArray<SCLFakeDevice *> *_devices;
    SCLFakeDevice *_defaultBack;
    SCLFakeDevice *_front;
}

+ (instancetype)shared {
    static SCLDeviceRegistry *registry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        registry = [SCLDeviceRegistry new];
    });
    return registry;
}

static SCLFakeDevice *SCLMakeDevice(AVCaptureDeviceType type, AVCaptureDevicePosition position, NSString *uid, NSString *name,
                                    CGFloat baseCrop, CGFloat maxZoom, NSArray<NSNumber *> *switchOver,
                                    NSArray<AVCaptureDevice *> *constituents, CGFloat displayMultiplier) {
    return [[SCLFakeDevice alloc] sclInitWithType:type
                                         position:position
                                         uniqueID:[@"dev.ifateam.simcamlite." stringByAppendingString:uid]
                                             name:name
                                         baseCrop:baseCrop
                                          maxZoom:maxZoom
                                       switchOver:switchOver
                                     constituents:constituents
                                displayMultiplier:displayMultiplier];
}

- (instancetype)init {
    if ((self = [super init])) {
        AVCaptureDevicePosition back = AVCaptureDevicePositionBack;
        uint32_t profile = SCLFrameReader.shared.deviceProfile;
        NSMutableArray<SCLFakeDevice *> *devices = [NSMutableArray array];

        if (profile == SCLDeviceProfileSingle) {
            _defaultBack = SCLMakeDevice(AVCaptureDeviceTypeBuiltInWideAngleCamera, back, @"back.wide", @"Back Camera", 1, 10, @[], @[], 1);
            [devices addObject:_defaultBack];
        } else {
            SCLFakeDevice *ultra = SCLMakeDevice(AVCaptureDeviceTypeBuiltInUltraWideCamera, back, @"back.ultrawide", @"Back Ultra Wide Camera", 1, 10, @[], @[], 1);
            SCLFakeDevice *wide = SCLMakeDevice(AVCaptureDeviceTypeBuiltInWideAngleCamera, back, @"back.wide", @"Back Camera", 2, 15, @[], @[], 1);
            _defaultBack = wide;
            [devices addObjectsFromArray:@[ultra, wide]];
            if (profile == SCLDeviceProfileTriple) {
                SCLFakeDevice *tele = SCLMakeDevice(AVCaptureDeviceTypeBuiltInTelephotoCamera, back, @"back.tele", @"Back Telephoto Camera", 6, 10, @[], @[], 1);
                SCLFakeDevice *triple = SCLMakeDevice(AVCaptureDeviceTypeBuiltInTripleCamera, back, @"back.triple", @"Back Triple Camera", 1, 30, @[@2, @6], @[ultra, wide, tele], 0.5);
                SCLFakeDevice *dual = SCLMakeDevice(AVCaptureDeviceTypeBuiltInDualCamera, back, @"back.dual", @"Back Dual Camera", 2, 15, @[@3], @[wide, tele], 1);
                [devices addObjectsFromArray:@[tele, triple, dual]];
            }
            SCLFakeDevice *dualWide = SCLMakeDevice(AVCaptureDeviceTypeBuiltInDualWideCamera, back, @"back.dualwide", @"Back Dual Wide Camera", 1, 20, @[@2], @[ultra, wide], 0.5);
            [devices addObject:dualWide];
            for (SCLFakeDevice *device in devices) {
                device.sclReferenceCrop = 2;
            }
        }

        _front = SCLMakeDevice(AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDevicePositionFront, @"front", @"Front Camera", 1, 5, @[], @[], 1);
        [devices addObject:_front];
        _devices = [devices copy];
        SCLLogInfo("Device registry ready (profile=%u, devices=%lu)", profile, (unsigned long)_devices.count);
    }
    return self;
}

- (SCLFakeDevice *)defaultBackDevice { return _defaultBack; }
- (SCLFakeDevice *)frontDevice { return _front; }

- (SCLFakeDevice *)deviceWithUniqueID:(NSString *)uniqueID {
    for (SCLFakeDevice *device in _devices) {
        if ([device.uniqueID isEqualToString:uniqueID]) {
            return device;
        }
    }
    return nil;
}

- (SCLFakeDevice *)deviceWithType:(AVCaptureDeviceType)type position:(AVCaptureDevicePosition)position {
    if (position == AVCaptureDevicePositionUnspecified) {
        SCLFakeDevice *back = [self deviceWithType:type position:AVCaptureDevicePositionBack];
        return back ?: [self deviceWithType:type position:AVCaptureDevicePositionFront];
    }
    for (SCLFakeDevice *device in _devices) {
        if ([device.deviceType isEqualToString:type] && device.position == position) {
            return device;
        }
    }
    return nil;
}

- (NSArray<SCLFakeDevice *> *)devicesWithTypes:(NSArray<AVCaptureDeviceType> *)types position:(AVCaptureDevicePosition)position {
    NSMutableArray<SCLFakeDevice *> *result = [NSMutableArray array];
    for (AVCaptureDeviceType type in types) {
        for (SCLFakeDevice *device in _devices) {
            BOOL positionMatches = position == AVCaptureDevicePositionUnspecified || device.position == position;
            if (positionMatches && [device.deviceType isEqualToString:type] && ![result containsObject:device]) {
                [result addObject:device];
            }
        }
    }
    return result;
}

@end
