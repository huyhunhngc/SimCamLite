#ifndef SCLSharedMemory_h
#define SCLSharedMemory_h

#include <stdint.h>
#include <time.h>

#define SCL_SHM_MAGIC 0x314C4353u
#define SCL_SHM_VERSION 1u
#define SCL_SHM_DIRECTORY "/Users/Shared/SimCamLite"
#define SCL_SHM_PATH "/Users/Shared/SimCamLite/frames.shm"

#define SCL_STREAM_COUNT 2
#define SCL_SLOT_COUNT 3
#define SCL_SENSOR_WIDTH 1920
#define SCL_SENSOR_HEIGHT 1440
#define SCL_MAX_CLIENTS 16
#define SCL_SLOT_BYTES ((uint64_t)SCL_SENSOR_WIDTH * SCL_SENSOR_HEIGHT * 4)
#define SCL_HEADER_BYTES 65536
#define SCL_SHM_BYTES (SCL_HEADER_BYTES + (uint64_t)SCL_STREAM_COUNT * SCL_SLOT_COUNT * SCL_SLOT_BYTES)
#define SCL_HOST_TIMEOUT_NS 2000000000ull
#define SCL_CLIENT_TIMEOUT_NS 3000000000ull

enum {
    SCLStreamBack = 0,
    SCLStreamFront = 1,
};

enum {
    SCLDeviceProfileTriple = 0,
    SCLDeviceProfileDualWide = 1,
    SCLDeviceProfileSingle = 2,
};

enum {
    SCLClientCameraIdle = 0,
    SCLClientCameraBack = 1,
    SCLClientCameraFront = 2,
};

typedef struct {
    volatile uint64_t sequence;
    uint32_t width;
    uint32_t height;
    uint32_t bytesPerRow;
    uint32_t pixelFormat;
    uint64_t timestampNs;
} SCLFrameSlot;

typedef struct {
    volatile uint64_t frameCounter;
    volatile uint32_t latestSlot;
    uint32_t reserved;
    SCLFrameSlot slots[SCL_SLOT_COUNT];
} SCLStreamHeader;

typedef struct {
    volatile int32_t pid;
    volatile uint32_t cameraState;
    volatile uint64_t heartbeatNs;
    volatile uint64_t framesDelivered;
    volatile uint64_t photoCount;
    uint32_t outputWidth;
    uint32_t outputHeight;
    char bundleID[128];
    char processName[64];
} SCLClientInfo;

typedef struct {
    uint32_t magic;
    uint32_t version;
    int32_t hostPID;
    volatile uint32_t deviceProfile;
    volatile uint64_t hostHeartbeatNs;
    SCLStreamHeader streams[SCL_STREAM_COUNT];
    SCLClientInfo clients[SCL_MAX_CLIENTS];
} SCLSharedHeader;

_Static_assert(sizeof(SCLSharedHeader) <= SCL_HEADER_BYTES, "SCLSharedHeader exceeds header region");

static inline uint64_t SCLNowNs(void) {
    return clock_gettime_nsec_np(CLOCK_REALTIME);
}

static inline uint8_t *SCLSlotData(void *base, int stream, int slot) {
    return (uint8_t *)base + SCL_HEADER_BYTES + ((uint64_t)stream * SCL_SLOT_COUNT + (uint64_t)slot) * SCL_SLOT_BYTES;
}

#endif
