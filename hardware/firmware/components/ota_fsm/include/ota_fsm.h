/*
 * ota_fsm — ESP32 OTA firmware update state machine.
 *
 * Pure C with no ESP-IDF dependencies so the same sources compile under the
 * host-test harness at hardware/firmware/test/host/. Follows the same
 * event-driven pattern as ble_reconnect and screen_fsm.
 *
 * The FSM tracks the full OTA lifecycle:
 *   IDLE → CHECKING → DOWNLOADING → VERIFYING → APPLYING → REBOOTING
 *   → CONFIRMING (back to IDLE) or ROLLBACK (back to IDLE).
 *
 * Download failures are retried up to max_retries times before entering
 * ERROR. All other failures transition directly to ERROR. The ERROR state
 * requires an explicit RESET event to return to IDLE.
 */
#ifndef SCRAMSCREEN_OTA_FSM_H
#define SCRAMSCREEN_OTA_FSM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    OTA_STATE_IDLE = 0,
    OTA_STATE_CHECKING = 1,
    OTA_STATE_DOWNLOADING = 2,
    OTA_STATE_VERIFYING = 3,
    OTA_STATE_APPLYING = 4,
    OTA_STATE_REBOOTING = 5,
    OTA_STATE_CONFIRMING = 6,
    OTA_STATE_ROLLBACK = 7,
    OTA_STATE_ERROR = 8,
} ota_state_t;

typedef enum {
    OTA_EVENT_CHECK_REQUESTED = 0,
    OTA_EVENT_VERSION_AVAILABLE = 1,
    OTA_EVENT_NO_UPDATE = 2,
    OTA_EVENT_DOWNLOAD_COMPLETE = 3,
    OTA_EVENT_DOWNLOAD_FAILED = 4,
    OTA_EVENT_VERIFY_OK = 5,
    OTA_EVENT_VERIFY_FAILED = 6,
    OTA_EVENT_APPLY_OK = 7,
    OTA_EVENT_APPLY_FAILED = 8,
    OTA_EVENT_BOOT_CONFIRMED = 9,
    OTA_EVENT_BOOT_FAILED = 10,
    OTA_EVENT_RESET = 11,
} ota_event_t;

typedef enum {
    OTA_ACTION_NONE = 0,
    OTA_ACTION_START_CHECK = 1,
    OTA_ACTION_START_DOWNLOAD = 2,
    OTA_ACTION_START_VERIFY = 3,
    OTA_ACTION_START_APPLY = 4,
    OTA_ACTION_REBOOT = 5,
    OTA_ACTION_CONFIRM_BOOT = 6,
    OTA_ACTION_ROLLBACK = 7,
    OTA_ACTION_REPORT_ERROR = 8,
} ota_action_t;

#define OTA_DEFAULT_MAX_RETRIES ((uint8_t)3)

typedef struct {
    ota_state_t state;
    uint8_t retry_count;
    uint8_t max_retries; /* default 3 */
} ota_fsm_t;

/*
 * Initialise the FSM to IDLE with default max_retries.
 */
void ota_fsm_init(ota_fsm_t *fsm);

/*
 * Feed one event into the FSM and return the action the caller must perform.
 */
ota_action_t ota_fsm_handle(ota_fsm_t *fsm, ota_event_t event);

/*
 * Human-readable name for a state, suitable for logging.
 */
const char *ota_state_name(ota_state_t state);

/*
 * Human-readable name for an action, suitable for logging.
 */
const char *ota_action_name(ota_action_t action);

#ifdef __cplusplus
}
#endif

#endif /* SCRAMSCREEN_OTA_FSM_H */
