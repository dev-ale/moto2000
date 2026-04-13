/*
 * ota_receiver — receives a framed firmware image over BLE and writes
 * it to the next OTA partition via esp_ota_*.
 *
 * Wire format (each call to ota_receiver_handle_frame is one BLE
 * write to the ota_data characteristic):
 *
 *   byte 0    : frame type
 *               0x01 BEGIN  — body: [size:4 LE][sha256:32]
 *               0x02 CHUNK  — body: raw firmware bytes
 *               0x03 COMMIT — body: empty (firmware reboots into new image)
 *               0x04 ABORT  — body: empty (cancel + drop partition state)
 *
 * The receiver is single-session; calling BEGIN while a session is
 * active aborts the previous one. SHA-256 of the received bytes is
 * verified against the announced hash before commit.
 */
#ifndef OTA_RECEIVER_H
#define OTA_RECEIVER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define OTA_FRAME_BEGIN  0x01
#define OTA_FRAME_CHUNK  0x02
#define OTA_FRAME_COMMIT 0x03
#define OTA_FRAME_ABORT  0x04

typedef enum {
    OTA_RX_IDLE = 0,
    OTA_RX_RECEIVING,
    OTA_RX_VERIFYING,
    OTA_RX_FAILED,
    OTA_RX_DONE,
} ota_rx_state_t;

/* Progress callback type — fires on every state transition AND every
 * CHUNK frame so the UI can draw a smooth progress bar. */
typedef void (*ota_receiver_progress_cb_t)(ota_rx_state_t state, uint32_t bytes_written,
                                           uint32_t total_size);

/* Initialise the receiver. Idempotent. */
void ota_receiver_init(void);

/* Set (or clear) the progress callback. Pass NULL to remove. */
void ota_receiver_set_progress_cb(ota_receiver_progress_cb_t cb);

/* Process one frame. `data[0]` is the frame type; `len` is the full
 * frame length including the type byte. Returns true on success. */
bool ota_receiver_handle_frame(const uint8_t *data, size_t len);

ota_rx_state_t ota_receiver_state(void);
uint32_t ota_receiver_bytes_written(void);
uint32_t ota_receiver_total_size(void);

#ifdef __cplusplus
}
#endif

#endif /* OTA_RECEIVER_H */
