/*
 * ota_fsm — implementation.
 *
 * See include/ota_fsm.h for the API contract. Pure C, no ESP-IDF includes.
 */
#include "ota_fsm.h"

void ota_fsm_init(ota_fsm_t *fsm)
{
    if (fsm == NULL) {
        return;
    }
    fsm->state = OTA_STATE_IDLE;
    fsm->retry_count = 0u;
    fsm->max_retries = OTA_DEFAULT_MAX_RETRIES;
}

ota_action_t ota_fsm_handle(ota_fsm_t *fsm, ota_event_t event)
{
    if (fsm == NULL) {
        return OTA_ACTION_NONE;
    }

    switch (fsm->state) {
    case OTA_STATE_IDLE:
        if (event == OTA_EVENT_CHECK_REQUESTED) {
            fsm->state = OTA_STATE_CHECKING;
            fsm->retry_count = 0u;
            return OTA_ACTION_START_CHECK;
        }
        return OTA_ACTION_NONE;

    case OTA_STATE_CHECKING:
        if (event == OTA_EVENT_VERSION_AVAILABLE) {
            fsm->state = OTA_STATE_DOWNLOADING;
            return OTA_ACTION_START_DOWNLOAD;
        }
        if (event == OTA_EVENT_NO_UPDATE) {
            fsm->state = OTA_STATE_IDLE;
            return OTA_ACTION_NONE;
        }
        return OTA_ACTION_NONE;

    case OTA_STATE_DOWNLOADING:
        if (event == OTA_EVENT_DOWNLOAD_COMPLETE) {
            fsm->state = OTA_STATE_VERIFYING;
            return OTA_ACTION_START_VERIFY;
        }
        if (event == OTA_EVENT_DOWNLOAD_FAILED) {
            fsm->retry_count = (uint8_t)(fsm->retry_count + 1u);
            if (fsm->retry_count < fsm->max_retries) {
                /* Stay in DOWNLOADING and retry. */
                return OTA_ACTION_START_DOWNLOAD;
            }
            fsm->state = OTA_STATE_ERROR;
            return OTA_ACTION_REPORT_ERROR;
        }
        return OTA_ACTION_NONE;

    case OTA_STATE_VERIFYING:
        if (event == OTA_EVENT_VERIFY_OK) {
            fsm->state = OTA_STATE_APPLYING;
            return OTA_ACTION_START_APPLY;
        }
        if (event == OTA_EVENT_VERIFY_FAILED) {
            fsm->state = OTA_STATE_ERROR;
            return OTA_ACTION_REPORT_ERROR;
        }
        return OTA_ACTION_NONE;

    case OTA_STATE_APPLYING:
        if (event == OTA_EVENT_APPLY_OK) {
            fsm->state = OTA_STATE_REBOOTING;
            return OTA_ACTION_REBOOT;
        }
        if (event == OTA_EVENT_APPLY_FAILED) {
            fsm->state = OTA_STATE_ERROR;
            return OTA_ACTION_REPORT_ERROR;
        }
        return OTA_ACTION_NONE;

    case OTA_STATE_REBOOTING:
        if (event == OTA_EVENT_BOOT_CONFIRMED) {
            fsm->state = OTA_STATE_IDLE;
            return OTA_ACTION_CONFIRM_BOOT;
        }
        if (event == OTA_EVENT_BOOT_FAILED) {
            fsm->state = OTA_STATE_ROLLBACK;
            return OTA_ACTION_ROLLBACK;
        }
        return OTA_ACTION_NONE;

    case OTA_STATE_CONFIRMING:
        /* CONFIRMING is a transient placeholder — not currently reachable
         * in the FSM flow (we go REBOOTING → IDLE directly on BOOT_CONFIRMED).
         * Included for completeness. */
        return OTA_ACTION_NONE;

    case OTA_STATE_ROLLBACK:
        /* After rollback the caller drives us back to IDLE via RESET. */
        if (event == OTA_EVENT_RESET) {
            fsm->state = OTA_STATE_IDLE;
            return OTA_ACTION_NONE;
        }
        return OTA_ACTION_NONE;

    case OTA_STATE_ERROR:
        if (event == OTA_EVENT_RESET) {
            fsm->state = OTA_STATE_IDLE;
            fsm->retry_count = 0u;
            return OTA_ACTION_NONE;
        }
        return OTA_ACTION_NONE;

    default:
        return OTA_ACTION_NONE;
    }
}

const char *ota_state_name(ota_state_t state)
{
    switch (state) {
    case OTA_STATE_IDLE:
        return "IDLE";
    case OTA_STATE_CHECKING:
        return "CHECKING";
    case OTA_STATE_DOWNLOADING:
        return "DOWNLOADING";
    case OTA_STATE_VERIFYING:
        return "VERIFYING";
    case OTA_STATE_APPLYING:
        return "APPLYING";
    case OTA_STATE_REBOOTING:
        return "REBOOTING";
    case OTA_STATE_CONFIRMING:
        return "CONFIRMING";
    case OTA_STATE_ROLLBACK:
        return "ROLLBACK";
    case OTA_STATE_ERROR:
        return "ERROR";
    default:
        return "UNKNOWN";
    }
}

const char *ota_action_name(ota_action_t action)
{
    switch (action) {
    case OTA_ACTION_NONE:
        return "NONE";
    case OTA_ACTION_START_CHECK:
        return "START_CHECK";
    case OTA_ACTION_START_DOWNLOAD:
        return "START_DOWNLOAD";
    case OTA_ACTION_START_VERIFY:
        return "START_VERIFY";
    case OTA_ACTION_START_APPLY:
        return "START_APPLY";
    case OTA_ACTION_REBOOT:
        return "REBOOT";
    case OTA_ACTION_CONFIRM_BOOT:
        return "CONFIRM_BOOT";
    case OTA_ACTION_ROLLBACK:
        return "ROLLBACK";
    case OTA_ACTION_REPORT_ERROR:
        return "REPORT_ERROR";
    default:
        return "UNKNOWN";
    }
}
