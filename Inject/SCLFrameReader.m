#import "SCLFrameReader.h"
#import "SCLRuntime.h"
#import <fcntl.h>
#import <stdatomic.h>
#import <sys/mman.h>
#import <unistd.h>

@implementation SCLFrameReader {
    void *_base;
    uint64_t _lastAttemptNs;
    int _clientIndex;
    uint64_t _cachedCounter[SCL_STREAM_COUNT];
    CVPixelBufferRef _cachedFrame[SCL_STREAM_COUNT];
    CVPixelBufferPoolRef _pool;
    uint32_t _poolWidth;
    uint32_t _poolHeight;
    dispatch_source_t _heartbeatTimer;
    NSString *_bundleID;
    NSString *_processName;
}

+ (instancetype)shared {
    static SCLFrameReader *reader;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        reader = [SCLFrameReader new];
    });
    return reader;
}

- (instancetype)init {
    if ((self = [super init])) {
        _clientIndex = -1;
        _bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
        _processName = NSProcessInfo.processInfo.processName ?: @"unknown";
    }
    return self;
}

- (SCLSharedHeader *)header {
    if (_base) {
        return (SCLSharedHeader *)_base;
    }
    uint64_t now = SCLNowNs();
    if (now - _lastAttemptNs < 1000000000ull) {
        return NULL;
    }
    _lastAttemptNs = now;

    int fd = open(SCL_SHM_PATH, O_RDWR);
    if (fd < 0) {
        return NULL;
    }
    void *base = mmap(NULL, SCL_SHM_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (base == MAP_FAILED) {
        SCLLogError("mmap failed: %{public}s", strerror(errno));
        return NULL;
    }
    SCLSharedHeader *header = (SCLSharedHeader *)base;
    if (header->magic != SCL_SHM_MAGIC || header->version != SCL_SHM_VERSION) {
        munmap(base, SCL_SHM_BYTES);
        return NULL;
    }
    _base = base;
    SCLLogInfo("Connected to host shared memory");
    return header;
}

- (BOOL)hostAlive {
    @synchronized (self) {
        SCLSharedHeader *header = [self header];
        return header && SCLNowNs() - header->hostHeartbeatNs < SCL_HOST_TIMEOUT_NS;
    }
}

- (uint32_t)deviceProfile {
    @synchronized (self) {
        SCLSharedHeader *header = [self header];
        if (!header) {
            return SCLDeviceProfileTriple;
        }
        uint32_t profile = header->deviceProfile;
        return profile <= SCLDeviceProfileSingle ? profile : SCLDeviceProfileTriple;
    }
}

- (CVPixelBufferRef)makeBufferWithWidth:(uint32_t)width height:(uint32_t)height {
    if (!_pool || _poolWidth != width || _poolHeight != height) {
        if (_pool) {
            CVPixelBufferPoolRelease(_pool);
            _pool = NULL;
        }
        NSDictionary *attributes = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @(width),
            (id)kCVPixelBufferHeightKey: @(height),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        };
        CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (__bridge CFDictionaryRef)attributes, &_pool);
        _poolWidth = width;
        _poolHeight = height;
    }
    CVPixelBufferRef buffer = NULL;
    if (_pool) {
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, _pool, &buffer);
    }
    return buffer;
}

- (CVPixelBufferRef)copyFrameForStream:(int)stream {
    if (stream < 0 || stream >= SCL_STREAM_COUNT) {
        return NULL;
    }
    @synchronized (self) {
        SCLSharedHeader *header = [self header];
        if (!header || SCLNowNs() - header->hostHeartbeatNs >= SCL_HOST_TIMEOUT_NS) {
            return NULL;
        }
        SCLStreamHeader *streamHeader = &header->streams[stream];
        uint64_t counter = streamHeader->frameCounter;
        if (counter == 0) {
            return NULL;
        }
        if (counter == _cachedCounter[stream] && _cachedFrame[stream]) {
            return CVPixelBufferRetain(_cachedFrame[stream]);
        }

        for (int attempt = 0; attempt < 3; attempt++) {
            uint32_t slotIndex = streamHeader->latestSlot % SCL_SLOT_COUNT;
            SCLFrameSlot *slot = &streamHeader->slots[slotIndex];
            uint64_t before = slot->sequence;
            if (before & 1) {
                continue;
            }
            atomic_thread_fence(memory_order_acquire);
            uint32_t width = slot->width;
            uint32_t height = slot->height;
            uint32_t sourceStride = slot->bytesPerRow;
            if (width == 0 || height == 0 || width > SCL_SENSOR_WIDTH || height > SCL_SENSOR_HEIGHT
                || sourceStride < width * 4 || (uint64_t)sourceStride * height > SCL_SLOT_BYTES) {
                return NULL;
            }
            CVPixelBufferRef buffer = [self makeBufferWithWidth:width height:height];
            if (!buffer) {
                return NULL;
            }
            CVPixelBufferLockBaseAddress(buffer, 0);
            uint8_t *destination = CVPixelBufferGetBaseAddress(buffer);
            size_t destinationStride = CVPixelBufferGetBytesPerRow(buffer);
            const uint8_t *source = SCLSlotData(_base, stream, (int)slotIndex);
            if (destinationStride == sourceStride) {
                memcpy(destination, source, (size_t)sourceStride * height);
            } else {
                for (uint32_t row = 0; row < height; row++) {
                    memcpy(destination + row * destinationStride, source + (size_t)row * sourceStride, (size_t)width * 4);
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, 0);
            atomic_thread_fence(memory_order_acquire);
            if (slot->sequence != before) {
                CVPixelBufferRelease(buffer);
                continue;
            }
            if (_cachedFrame[stream]) {
                CVPixelBufferRelease(_cachedFrame[stream]);
            }
            _cachedFrame[stream] = CVPixelBufferRetain(buffer);
            _cachedCounter[stream] = counter;
            return buffer;
        }
        return _cachedFrame[stream] ? CVPixelBufferRetain(_cachedFrame[stream]) : NULL;
    }
}

- (SCLClientInfo *)client {
    SCLSharedHeader *header = [self header];
    if (!header) {
        return NULL;
    }
    int32_t pid = getpid();
    if (_clientIndex >= 0 && header->clients[_clientIndex].pid == pid) {
        return &header->clients[_clientIndex];
    }
    uint64_t now = SCLNowNs();
    int candidate = -1;
    for (int i = 0; i < SCL_MAX_CLIENTS; i++) {
        SCLClientInfo *info = &header->clients[i];
        if (info->pid == pid) {
            candidate = i;
            break;
        }
        if (candidate < 0 && (info->pid == 0 || now - info->heartbeatNs > SCL_CLIENT_TIMEOUT_NS)) {
            candidate = i;
        }
    }
    if (candidate < 0) {
        return NULL;
    }
    SCLClientInfo *info = &header->clients[candidate];
    memset(info, 0, sizeof(*info));
    strlcpy(info->bundleID, _bundleID.UTF8String, sizeof(info->bundleID));
    strlcpy(info->processName, _processName.UTF8String, sizeof(info->processName));
    info->heartbeatNs = now;
    info->pid = pid;
    _clientIndex = candidate;
    return info;
}

- (void)reportCameraState:(uint32_t)state width:(uint32_t)width height:(uint32_t)height {
    @synchronized (self) {
        SCLClientInfo *info = [self client];
        if (info) {
            info->cameraState = state;
            info->outputWidth = width;
            info->outputHeight = height;
            info->heartbeatNs = SCLNowNs();
        }
    }
}

- (void)reportFrameDelivered {
    @synchronized (self) {
        SCLClientInfo *info = [self client];
        if (info) {
            info->framesDelivered += 1;
        }
    }
}

- (void)reportPhotoCaptured {
    @synchronized (self) {
        SCLClientInfo *info = [self client];
        if (info) {
            info->photoCount += 1;
        }
    }
}

- (void)startHeartbeat {
    if (_heartbeatTimer) {
        return;
    }
    dispatch_queue_t queue = dispatch_queue_create("dev.ifateam.simcamlite.heartbeat", DISPATCH_QUEUE_SERIAL);
    _heartbeatTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(_heartbeatTimer, dispatch_time(DISPATCH_TIME_NOW, 0), NSEC_PER_SEC / 2, NSEC_PER_SEC / 10);
    __weak SCLFrameReader *weakSelf = self;
    dispatch_source_set_event_handler(_heartbeatTimer, ^{
        SCLFrameReader *reader = weakSelf;
        if (!reader) {
            return;
        }
        @synchronized (reader) {
            SCLClientInfo *info = [reader client];
            if (info) {
                info->heartbeatNs = SCLNowNs();
            }
        }
    });
    dispatch_resume(_heartbeatTimer);
}

@end
