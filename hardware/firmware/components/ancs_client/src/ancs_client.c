/*
 * ancs_client.c — NimBLE GATT client wrapper for the Apple Notification
 * Center Service.
 *
 * Discovery sequence after a connection comes up:
 *   1. ble_gattc_disc_svc_by_uuid(ANCS_SERVICE)
 *   2. ble_gattc_disc_all_chrs() to find Notification Source, Data
 *      Source, and Control Point characteristics
 *   3. ble_gattc_disc_all_dscs() on each notify characteristic
 *   4. Write 0x0001 to each CCCD
 *
 * Notifications then arrive via BLE_GAP_EVENT_NOTIFY_RX. We forward to
 * ancs_client_handle_notification(), which routes by attribute handle.
 *
 * Currently we only react to incoming-call events. The first version
 * does NOT request the caller name via the Control Point — it just
 * shows "Incoming call" with an empty caller handle. (The Data Source
 * round-trip can be added later; the parser already supports it.)
 */
#include "ancs_client.h"
#include "ancs_parser.h"

#include <string.h>

#include "esp_log.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_uuid.h"

#define TAG "ancs_client"

/* ANCS service / characteristic UUIDs in little-endian byte order. */
static const ble_uuid128_t ANCS_SERVICE = BLE_UUID128_INIT(
    0xD0, 0x00, 0x2D, 0x12, 0x1E, 0x4B, 0x0F, 0xA4, 0x99, 0x4E, 0xCE, 0xB5, 0x31, 0xF4, 0x05, 0x79);

static const ble_uuid128_t ANCS_NOTIFICATION_SOURCE = BLE_UUID128_INIT(
    0xBD, 0x1D, 0xA2, 0x99, 0xE6, 0x25, 0x58, 0x8C, 0xD9, 0x42, 0x01, 0x63, 0x0D, 0x12, 0xBF, 0x9F);

static const ble_uuid128_t ANCS_CONTROL_POINT = BLE_UUID128_INIT(
    0xD9, 0xD9, 0xAA, 0xFD, 0xBD, 0x9B, 0x21, 0x98, 0xA8, 0x49, 0xE1, 0x45, 0xF3, 0xD8, 0xD1, 0x69);

static const ble_uuid128_t ANCS_DATA_SOURCE = BLE_UUID128_INIT(
    0xFB, 0x7B, 0x7C, 0xCE, 0x6A, 0xB3, 0x44, 0xBE, 0xB5, 0x4B, 0xD6, 0x24, 0xE9, 0xC6, 0xEA, 0x22);

static struct {
    bool in_use;
    uint16_t conn_handle;
    uint16_t svc_end_handle;
    uint16_t notification_source_handle;
    uint16_t data_source_handle;
    uint16_t control_point_handle;
} s_ctx;

static ancs_client_call_cb_t s_on_call_event;

static void emit_call(ble_call_state_t state, const char *handle_str)
{
    if (!s_on_call_event) {
        return;
    }
    ble_incoming_call_data_t data = { 0 };
    data.call_state = state;
    snprintf(data.caller_handle, sizeof(data.caller_handle), "%s", handle_str ? handle_str : "");
    s_on_call_event(&data);
}

/* Forward declarations. */
static int on_chr_discovered(uint16_t conn_handle, const struct ble_gatt_error *error,
                             const struct ble_gatt_chr *chr, void *arg);
static int on_svc_discovered(uint16_t conn_handle, const struct ble_gatt_error *error,
                             const struct ble_gatt_svc *svc, void *arg);
static int on_cccd_written(uint16_t conn_handle, const struct ble_gatt_error *error,
                           struct ble_gatt_attr *attr, void *arg);

static int on_cccd_written(uint16_t conn_handle, const struct ble_gatt_error *error,
                           struct ble_gatt_attr *attr, void *arg)
{
    (void)conn_handle;
    (void)attr;
    (void)arg;
    if (error->status != 0) {
        ESP_LOGW(TAG, "ANCS CCCD write failed: status=%d", error->status);
    } else {
        ESP_LOGI(TAG, "ANCS CCCD write ok");
    }
    return 0;
}

static int on_any_dsc_discovered(uint16_t conn_handle, const struct ble_gatt_error *error,
                                 uint16_t chr_val_handle, const struct ble_gatt_dsc *dsc, void *arg)
{
    (void)chr_val_handle;
    (void)arg;
    if (error->status != 0 || dsc == NULL) {
        return 0;
    }
    if (ble_uuid_cmp(&dsc->uuid.u, BLE_UUID16_DECLARE(BLE_GATT_DSC_CLT_CFG_UUID16)) == 0) {
        ESP_LOGI(TAG, "ANCS CCCD discovered at handle %d", dsc->handle);
        const uint8_t cccd_val[2] = { 0x01, 0x00 };
        int rc = ble_gattc_write_flat(conn_handle, dsc->handle, cccd_val, sizeof(cccd_val),
                                      on_cccd_written, NULL);
        if (rc != 0) {
            ESP_LOGW(TAG, "ANCS CCCD write dispatch failed: rc=%d", rc);
        }
    }
    return 0;
}

static void enable_cccd(uint16_t conn_handle, uint16_t val_handle)
{
    /* Discover descriptors in a tight range right after the value
     * handle so we're guaranteed to only see this characteristic's own
     * CCCD and not an adjacent characteristic's descriptor. */
    uint16_t end_handle = (uint16_t)(val_handle + 3);
    if (end_handle > s_ctx.svc_end_handle) {
        end_handle = s_ctx.svc_end_handle;
    }
    int rc =
        ble_gattc_disc_all_dscs(conn_handle, val_handle, end_handle, on_any_dsc_discovered, NULL);
    if (rc != 0) {
        ESP_LOGW(TAG, "ANCS disc_all_dscs failed: rc=%d", rc);
    }
}

static int on_chr_discovered(uint16_t conn_handle, const struct ble_gatt_error *error,
                             const struct ble_gatt_chr *chr, void *arg)
{
    (void)arg;
    if (error->status != 0 || chr == NULL) {
        /* Discovery complete — subscribe to the notify characteristics. */
        if (s_ctx.notification_source_handle != 0) {
            enable_cccd(conn_handle, s_ctx.notification_source_handle);
        }
        if (s_ctx.data_source_handle != 0) {
            enable_cccd(conn_handle, s_ctx.data_source_handle);
        }
        return 0;
    }
    if (ble_uuid_cmp(&chr->uuid.u, &ANCS_NOTIFICATION_SOURCE.u) == 0) {
        s_ctx.notification_source_handle = chr->val_handle;
        ESP_LOGI(TAG, "ANCS Notification Source at handle %d", chr->val_handle);
    } else if (ble_uuid_cmp(&chr->uuid.u, &ANCS_DATA_SOURCE.u) == 0) {
        s_ctx.data_source_handle = chr->val_handle;
        ESP_LOGI(TAG, "ANCS Data Source at handle %d", chr->val_handle);
    } else if (ble_uuid_cmp(&chr->uuid.u, &ANCS_CONTROL_POINT.u) == 0) {
        s_ctx.control_point_handle = chr->val_handle;
    }
    return 0;
}

static int on_svc_discovered(uint16_t conn_handle, const struct ble_gatt_error *error,
                             const struct ble_gatt_svc *svc, void *arg)
{
    (void)arg;
    if (error->status != 0 || svc == NULL) {
        if (svc == NULL && error->status != BLE_HS_EDONE) {
            ESP_LOGW(TAG, "ANCS service not found");
        }
        return 0;
    }
    s_ctx.svc_end_handle = svc->end_handle;
    ESP_LOGI(TAG, "ANCS service handles %d..%d", svc->start_handle, svc->end_handle);
    ble_gattc_disc_all_chrs(conn_handle, svc->start_handle, svc->end_handle, on_chr_discovered,
                            NULL);
    return 0;
}

/* ----------------------------------------------------------------------- */
/* Public API                                                               */
/* ----------------------------------------------------------------------- */

void ancs_client_init(ancs_client_call_cb_t on_call_event)
{
    s_on_call_event = on_call_event;
    memset(&s_ctx, 0, sizeof(s_ctx));
}

void ancs_client_start_for_connection(uint16_t conn_handle)
{
    memset(&s_ctx, 0, sizeof(s_ctx));
    s_ctx.in_use = true;
    s_ctx.conn_handle = conn_handle;

    int rc = ble_gattc_disc_svc_by_uuid(conn_handle, &ANCS_SERVICE.u, on_svc_discovered, NULL);
    if (rc != 0) {
        ESP_LOGW(TAG, "ble_gattc_disc_svc_by_uuid failed: rc=%d", rc);
    }
}

void ancs_client_handle_disconnect(uint16_t conn_handle)
{
    if (s_ctx.in_use && s_ctx.conn_handle == conn_handle) {
        memset(&s_ctx, 0, sizeof(s_ctx));
    }
}

bool ancs_client_handle_notification(uint16_t conn_handle, uint16_t attr_handle,
                                     const uint8_t *data, size_t len)
{
    if (!s_ctx.in_use || s_ctx.conn_handle != conn_handle) {
        return false;
    }
    if (attr_handle == s_ctx.notification_source_handle) {
        ancs_notification_t note;
        if (!ancs_parse_notification_source(data, len, &note)) {
            return true;
        }
        if (note.category_id != ANCS_CATEGORY_INCOMING_CALL &&
            note.category_id != ANCS_CATEGORY_MISSED_CALL) {
            return true; /* Not a call, ignore. */
        }
        if (note.event_id == ANCS_EVENT_ADDED) {
            ESP_LOGI(TAG, "incoming call uid=%lu", (unsigned long)note.uid);
            emit_call(BLE_CALL_INCOMING, "");
        } else if (note.event_id == ANCS_EVENT_REMOVED) {
            ESP_LOGI(TAG, "call ended uid=%lu", (unsigned long)note.uid);
            emit_call(BLE_CALL_ENDED, "");
        }
        return true;
    }
    if (attr_handle == s_ctx.data_source_handle) {
        /* Data Source notifications carry the requested attribute values.
         * Not used in this first cut. */
        return true;
    }
    return false;
}
