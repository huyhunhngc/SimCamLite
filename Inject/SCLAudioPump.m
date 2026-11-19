#import "SCLAudioPump.h"
#import "SCLRuntime.h"
#import "SCLSessionState.h"
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static const void *SCLAudioDelegateKey = &SCLAudioDelegateKey;
static const void *SCLAudioQueueKey = &SCLAudioQueueKey;

static const Float64 SCLAudioSampleRate = 48000;
static const UInt32 SCLAudioFramesPerBuffer = 1024;
static const UInt32 SCLAudioBytesPerFrame = 2;
static const int SCLAudioBufferCount = 3;

void SCLSetAudioDataDelegate(AVCaptureAudioDataOutput *output, id delegate, dispatch_queue_t queue) {
    objc_setAssociatedObject(output, SCLAudioDelegateKey, delegate ? [SCLWeakBox boxWithValue:delegate] : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(output, SCLAudioQueueKey, queue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static AudioStreamBasicDescription SCLAudioDescription(void) {
    AudioStreamBasicDescription description = {0};
    description.mSampleRate = SCLAudioSampleRate;
    description.mFormatID = kAudioFormatLinearPCM;
    description.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    description.mChannelsPerFrame = 1;
    description.mBitsPerChannel = 16;
    description.mBytesPerFrame = SCLAudioBytesPerFrame;
    description.mFramesPerPacket = 1;
    description.mBytesPerPacket = SCLAudioBytesPerFrame;
    return description;
}

static BOOL SCLAudioNeeded(void) {
    for (SCLSessionState *state in SCLRunningSessionStates()) {
        if (state.audioInputs.count == 0) {
            continue;
        }
        for (AVCaptureOutput *output in state.managedOutputs) {
            if ([output isKindOfClass:AVCaptureAudioDataOutput.class]) {
                return YES;
            }
        }
    }
    return NO;
}

@interface SCLAudioPump ()
- (void)deliverBytes:(nullable const void *)bytes length:(UInt32)length pts:(CMTime)pts;
@end

static void SCLAudioInputCallback(void *user, AudioQueueRef queue, AudioQueueBufferRef buffer, const AudioTimeStamp *start,
                                  UInt32 packets, const AudioStreamPacketDescription *descriptions) {
    SCLAudioPump *pump = (__bridge SCLAudioPump *)user;
    if (buffer->mAudioDataByteSize > 0) {
        CMTime pts = (start->mFlags & kAudioTimeStampHostTimeValid)
            ? CMClockMakeHostTimeFromSystemUnits(start->mHostTime)
            : CMClockGetTime(CMClockGetHostTimeClock());
        [pump deliverBytes:buffer->mAudioData length:buffer->mAudioDataByteSize pts:pts];
    }
    AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
}

@implementation SCLAudioPump {
    dispatch_queue_t _control;
    AudioQueueRef _queue;
    dispatch_source_t _silenceTimer;
    CMTime _silenceNext;
    CMAudioFormatDescriptionRef _format;
}

+ (instancetype)shared {
    static SCLAudioPump *pump;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pump = [SCLAudioPump new];
    });
    return pump;
}

- (instancetype)init {
    if ((self = [super init])) {
        _control = dispatch_queue_create("dev.ifateam.simcamlite.audio", DISPATCH_QUEUE_SERIAL);
        AudioStreamBasicDescription description = SCLAudioDescription();
        CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &description, 0, NULL, 0, NULL, NULL, &_format);
    }
    return self;
}

- (void)sessionStatesDidChange {
    dispatch_async(_control, ^{
        BOOL needed = SCLAudioNeeded();
        BOOL active = self->_queue != NULL || self->_silenceTimer != nil;
        if (needed && !active) {
            [self start];
        } else if (!needed && active) {
            [self stop];
        }
    });
}

- (void)start {
    if ([self startMicrophone]) {
        SCLLogInfo("Audio pump started (microphone)");
        return;
    }
    [self startSilence];
    SCLLogInfo("Audio pump started (silence)");
}

- (BOOL)startMicrophone {
    AVAudioSession *session = AVAudioSession.sharedInstance;
    if (session.recordPermission != AVAudioSessionRecordPermissionGranted) {
        return NO;
    }
    if (![session.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]
        && ![session.category isEqualToString:AVAudioSessionCategoryRecord]) {
        [session setCategory:AVAudioSessionCategoryPlayAndRecord
                        mode:AVAudioSessionModeVideoRecording
                     options:AVAudioSessionCategoryOptionDefaultToSpeaker
                       error:NULL];
    }
    [session setActive:YES error:NULL];

    AudioStreamBasicDescription description = SCLAudioDescription();
    AudioQueueRef queue = NULL;
    OSStatus status = AudioQueueNewInput(&description, SCLAudioInputCallback, (__bridge void *)self, NULL, NULL, 0, &queue);
    if (status != noErr) {
        SCLLogError("AudioQueueNewInput failed (%d)", (int)status);
        return NO;
    }
    for (int i = 0; i < SCLAudioBufferCount; i++) {
        AudioQueueBufferRef buffer = NULL;
        if (AudioQueueAllocateBuffer(queue, SCLAudioFramesPerBuffer * SCLAudioBytesPerFrame, &buffer) == noErr) {
            AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
        }
    }
    status = AudioQueueStart(queue, NULL);
    if (status != noErr) {
        SCLLogError("AudioQueueStart failed (%d)", (int)status);
        AudioQueueDispose(queue, true);
        return NO;
    }
    _queue = queue;
    return YES;
}

- (void)startSilence {
    _silenceNext = CMClockGetTime(CMClockGetHostTimeClock());
    uint64_t interval = (uint64_t)(SCLAudioFramesPerBuffer / SCLAudioSampleRate * NSEC_PER_SEC);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _control);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)interval), interval, interval / 10);
    __weak SCLAudioPump *weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        [weakSelf emitSilence];
    });
    dispatch_resume(timer);
    _silenceTimer = timer;
}

- (void)emitSilence {
    CMTime step = CMTimeMake(SCLAudioFramesPerBuffer, (int32_t)SCLAudioSampleRate);
    CMTime now = CMClockGetTime(CMClockGetHostTimeClock());
    if (CMTimeGetSeconds(CMTimeSubtract(now, _silenceNext)) > 0.5) {
        _silenceNext = CMTimeSubtract(now, step);
    }
    while (CMTimeCompare(CMTimeAdd(_silenceNext, step), now) <= 0) {
        [self deliverBytes:NULL length:SCLAudioFramesPerBuffer * SCLAudioBytesPerFrame pts:_silenceNext];
        _silenceNext = CMTimeAdd(_silenceNext, step);
    }
}

- (void)stop {
    if (_queue) {
        AudioQueueStop(_queue, true);
        AudioQueueDispose(_queue, true);
        _queue = NULL;
    }
    if (_silenceTimer) {
        dispatch_source_cancel(_silenceTimer);
        _silenceTimer = nil;
    }
    SCLLogInfo("Audio pump stopped");
}

- (CMSampleBufferRef)makeSampleWithBytes:(const void *)bytes length:(UInt32)length pts:(CMTime)pts CF_RETURNS_RETAINED {
    CMBlockBufferRef block = NULL;
    if (CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, NULL, length, kCFAllocatorDefault, NULL, 0, length,
                                           kCMBlockBufferAssureMemoryNowFlag, &block) != kCMBlockBufferNoErr) {
        return NULL;
    }
    if (bytes) {
        CMBlockBufferReplaceDataBytes(bytes, block, 0, length);
    } else {
        CMBlockBufferFillDataBytes(0, block, 0, length);
    }
    CMSampleBufferRef sample = NULL;
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(kCFAllocatorDefault, block, _format, length / SCLAudioBytesPerFrame, pts, NULL, &sample);
    CFRelease(block);
    return sample;
}

- (void)deliverBytes:(const void *)bytes length:(UInt32)length pts:(CMTime)pts {
    CMSampleBufferRef sample = NULL;
    for (SCLSessionState *state in SCLRunningSessionStates()) {
        AVCaptureSession *session = state.session;
        if (!session || state.audioInputs.count == 0) {
            continue;
        }
        for (AVCaptureOutput *output in state.managedOutputs) {
            if (![output isKindOfClass:AVCaptureAudioDataOutput.class]) {
                continue;
            }
            id<AVCaptureAudioDataOutputSampleBufferDelegate> delegate = ((SCLWeakBox *)objc_getAssociatedObject(output, SCLAudioDelegateKey)).value;
            dispatch_queue_t queue = objc_getAssociatedObject(output, SCLAudioQueueKey);
            if (!delegate || !queue || ![delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
                continue;
            }
            SCLFakeConnection *connection = SCLConnectionForOutput(output, session);
            if (!connection.isEnabled) {
                continue;
            }
            if (!sample) {
                sample = [self makeSampleWithBytes:bytes length:length pts:pts];
                if (!sample) {
                    return;
                }
            }
            CFRetain(sample);
            AVCaptureAudioDataOutput *audioOutput = (AVCaptureAudioDataOutput *)output;
            dispatch_async(queue, ^{
                [delegate captureOutput:audioOutput didOutputSampleBuffer:sample fromConnection:connection];
                CFRelease(sample);
            });
        }
    }
    if (sample) {
        CFRelease(sample);
    }
}

@end
