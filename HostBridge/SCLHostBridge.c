#include "SCLHostBridge.h"
#include <fcntl.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

static void *scl_base;

static SCLSharedHeader *scl_header(void) {
    return (SCLSharedHeader *)scl_base;
}

bool scl_host_open(void) {
    if (scl_base) {
        return true;
    }
    mkdir(SCL_SHM_DIRECTORY, 0777);
    chmod(SCL_SHM_DIRECTORY, 0777);
    int fd = open(SCL_SHM_PATH, O_RDWR | O_CREAT, 0666);
    if (fd < 0) {
        return false;
    }
    fchmod(fd, 0666);
    struct stat info;
    if (fstat(fd, &info) != 0 || (uint64_t)info.st_size != SCL_SHM_BYTES) {
        if (ftruncate(fd, (off_t)SCL_SHM_BYTES) != 0) {
            close(fd);
            return false;
        }
    }
    void *base = mmap(NULL, SCL_SHM_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (base == MAP_FAILED) {
        return false;
    }
    SCLSharedHeader *header = (SCLSharedHeader *)base;
    if (header->magic != SCL_SHM_MAGIC || header->version != SCL_SHM_VERSION) {
        memset(header, 0, sizeof(SCLSharedHeader));
        header->version = SCL_SHM_VERSION;
        atomic_thread_fence(memory_order_release);
        header->magic = SCL_SHM_MAGIC;
    }
    for (int stream = 0; stream < SCL_STREAM_COUNT; stream++) {
        for (int slot = 0; slot < SCL_SLOT_COUNT; slot++) {
            SCLFrameSlot *frame = &header->streams[stream].slots[slot];
            if (frame->sequence & 1) {
                frame->sequence += 1;
            }
        }
    }
    header->hostPID = getpid();
    scl_base = base;
    return true;
}

void scl_host_close(void) {
    if (!scl_base) {
        return;
    }
    scl_header()->hostHeartbeatNs = 0;
    scl_header()->hostPID = 0;
    msync(scl_base, SCL_HEADER_BYTES, MS_ASYNC);
    munmap(scl_base, SCL_SHM_BYTES);
    scl_base = NULL;
}

bool scl_host_is_open(void) {
    return scl_base != NULL;
}

uint8_t *scl_host_begin_frame(int stream, int *slot_out) {
    if (!scl_base || stream < 0 || stream >= SCL_STREAM_COUNT) {
        return NULL;
    }
    SCLStreamHeader *header = &scl_header()->streams[stream];
    int slot = (int)((header->latestSlot + 1) % SCL_SLOT_COUNT);
    header->slots[slot].sequence += 1;
    atomic_thread_fence(memory_order_release);
    if (slot_out) {
        *slot_out = slot;
    }
    return SCLSlotData(scl_base, stream, slot);
}

void scl_host_end_frame(int stream, int slot, uint32_t width, uint32_t height, uint32_t bytes_per_row) {
    if (!scl_base || stream < 0 || stream >= SCL_STREAM_COUNT || slot < 0 || slot >= SCL_SLOT_COUNT) {
        return;
    }
    SCLStreamHeader *header = &scl_header()->streams[stream];
    SCLFrameSlot *frame = &header->slots[slot];
    frame->width = width;
    frame->height = height;
    frame->bytesPerRow = bytes_per_row;
    frame->pixelFormat = 'BGRA';
    frame->timestampNs = SCLNowNs();
    atomic_thread_fence(memory_order_release);
    frame->sequence += 1;
    atomic_thread_fence(memory_order_release);
    header->latestSlot = (uint32_t)slot;
    header->frameCounter += 1;
}

void scl_host_heartbeat(uint32_t device_profile) {
    if (!scl_base) {
        return;
    }
    scl_header()->deviceProfile = device_profile;
    scl_header()->hostPID = getpid();
    scl_header()->hostHeartbeatNs = SCLNowNs();
}

bool scl_host_read_client(int index, SCLClientInfo *out) {
    if (!scl_base || index < 0 || index >= SCL_MAX_CLIENTS || !out) {
        return false;
    }
    SCLClientInfo *client = &scl_header()->clients[index];
    if (client->pid <= 0 || SCLNowNs() - client->heartbeatNs > SCL_CLIENT_TIMEOUT_NS) {
        return false;
    }
    memcpy(out, client, sizeof(SCLClientInfo));
    out->bundleID[sizeof(out->bundleID) - 1] = 0;
    out->processName[sizeof(out->processName) - 1] = 0;
    return true;
}
