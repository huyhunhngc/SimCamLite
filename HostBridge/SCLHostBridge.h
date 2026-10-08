#ifndef SCLHostBridge_h
#define SCLHostBridge_h

#include <stdbool.h>
#include "SCLSharedMemory.h"

bool scl_host_open(void);
void scl_host_close(void);
bool scl_host_is_open(void);
uint8_t *scl_host_begin_frame(int stream, int *slot_out);
void scl_host_end_frame(int stream, int slot, uint32_t width, uint32_t height, uint32_t bytes_per_row);
void scl_host_heartbeat(uint32_t device_profile);
bool scl_host_read_client(int index, SCLClientInfo *out);

#endif
