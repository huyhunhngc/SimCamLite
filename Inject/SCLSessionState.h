#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import "SCLFakes.h"

NS_ASSUME_NONNULL_BEGIN

@interface SCLSessionState : NSObject

@property (nonatomic, weak, readonly, nullable) AVCaptureSession *session;
@property (atomic) BOOL running;
@property (atomic, copy, nullable) AVCaptureSessionPreset preset;
@property (atomic, strong, nullable) CIImage *latestSensorImage;
@property (nonatomic) uint64_t lastFrameCounter;
@property (nonatomic) uint64_t lastDeliveryNs;
@property (nonatomic, weak, nullable) SCLFakeDevice *lastDevice;
@property (nonatomic, readonly, nullable) SCLFakeDevice *activeDevice;
@property (nonatomic, readonly) NSArray<SCLFakeDeviceInput *> *fakeInputs;
@property (nonatomic, readonly) NSArray<AVCaptureOutput *> *managedOutputs;
@property (nonatomic, readonly) NSArray<AVCaptureVideoPreviewLayer *> *previewLayers;

- (BOOL)containsInput:(AVCaptureInput *)input;
- (void)addInput:(SCLFakeDeviceInput *)input;
- (void)removeInput:(AVCaptureInput *)input;
- (BOOL)containsOutput:(AVCaptureOutput *)output;
- (void)addOutput:(AVCaptureOutput *)output;
- (void)removeOutput:(AVCaptureOutput *)output;
- (void)addPreviewLayer:(AVCaptureVideoPreviewLayer *)layer;

@end

SCLSessionState *_Nullable SCLStateForSession(AVCaptureSession *session, BOOL create);
NSArray<SCLSessionState *> *SCLRunningSessionStates(void);
void SCLSetSessionStateRunning(SCLSessionState *state, BOOL running);

BOOL SCLIsManagedOutput(AVCaptureOutput *output);
AVCaptureSession *_Nullable SCLSessionForOutput(AVCaptureOutput *output);
void SCLSetSessionForOutput(AVCaptureOutput *output, AVCaptureSession *_Nullable session);
SCLFakeConnection *SCLConnectionForOutput(AVCaptureOutput *output, AVCaptureSession *session);
SCLFakeConnection *SCLConnectionForPreviewLayer(AVCaptureVideoPreviewLayer *layer, AVCaptureSession *session);

@interface SCLDeviceRegistry : NSObject

+ (instancetype)shared;

@property (nonatomic, readonly) NSArray<SCLFakeDevice *> *devices;
@property (nonatomic, readonly) SCLFakeDevice *defaultBackDevice;
@property (nonatomic, readonly) SCLFakeDevice *frontDevice;

- (nullable SCLFakeDevice *)deviceWithUniqueID:(NSString *)uniqueID;
- (nullable SCLFakeDevice *)deviceWithType:(AVCaptureDeviceType)type position:(AVCaptureDevicePosition)position;
- (NSArray<SCLFakeDevice *> *)devicesWithTypes:(NSArray<AVCaptureDeviceType> *)types position:(AVCaptureDevicePosition)position;

@end

NS_ASSUME_NONNULL_END
