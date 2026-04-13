/*
 * ble_server.c — NimBLE GATT server for the ScramScreen dashboard.
 *
 * ESP-IDF v5.3+ only. Uses the static GATT table approach
 * (ble_gatt_svc_def arrays) which is cleaner than runtime registration.
 *
 * Characteristic UUIDs from docs/ble-protocol.md:
 *   screen_data  3ad9d5d0-1d70-4edf-b2cc-bf1d84dc545b  write + write-no-rsp
 *   control      160c1f54-82ec-45e2-8339-1680f16c1a94  write
 *   status       b7066d36-d896-4e74-9648-500df789d969  notify + read
 *
 * Service UUID:  b6ca8101-b172-4d33-8518-8b1700235ed2
 */

#include "ble_server.h"

#include "host/ble_hs.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_store.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "ams_client.h"
#include "ancs_client.h"

#include "esp_log.h"
#include "esp_timer.h"

#include <string.h>

static const char *TAG = "ble_server";

/* ----------------------------------------------------------------------- */
/* UUIDs — 128-bit, stored in little-endian byte order for NimBLE          */
/* ----------------------------------------------------------------------- */

/* Service: b6ca8101-b172-4d33-8518-8b1700235ed2 */
static const ble_uuid128_t s_svc_uuid = BLE_UUID128_INIT(
    0xd2, 0x5e, 0x23, 0x00, 0x17, 0x8b, 0x18, 0x85, 0x33, 0x4d, 0x72, 0xb1, 0x01, 0x81, 0xca, 0xb6);

/* screen_data: 3ad9d5d0-1d70-4edf-b2cc-bf1d84dc545b */
static const ble_uuid128_t s_screen_data_uuid = BLE_UUID128_INIT(
    0x5b, 0x54, 0xdc, 0x84, 0x1d, 0xbf, 0xcc, 0xb2, 0xdf, 0x4e, 0x70, 0x1d, 0xd0, 0xd5, 0xa9, 0x3a);

/* control: 160c1f54-82ec-45e2-8339-1680f16c1a94 */
static const ble_uuid128_t s_control_uuid = BLE_UUID128_INIT(
    0x94, 0x1a, 0x6c, 0xf1, 0x80, 0x16, 0x39, 0x83, 0xe2, 0x45, 0xec, 0x82, 0x54, 0x1f, 0x0c, 0x16);

/* status: b7066d36-d896-4e74-9648-500df789d969 */
static const ble_uuid128_t s_status_uuid = BLE_UUID128_INIT(
    0x69, 0xd9, 0x89, 0xf7, 0x0d, 0x50, 0x48, 0x96, 0x74, 0x4e, 0x96, 0xd8, 0x36, 0x6d, 0x06, 0xb7);

/* ----------------------------------------------------------------------- */
/* Module state                                                             */
/* ----------------------------------------------------------------------- */

static ble_server_callbacks_t s_callbacks;
static uint16_t s_conn_handle;
static bool s_connected;
static uint16_t s_status_val_handle;

/* ----------------------------------------------------------------------- */
/* GATT access callbacks                                                    */
/* ----------------------------------------------------------------------- */

static int prv_screen_data_access(uint16_t conn_handle, uint16_t attr_handle,
                                  struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    /* Flatten the mbuf chain into a contiguous buffer. */
    uint16_t om_len = OS_MBUF_PKTLEN(ctxt->om);
    uint8_t buf[256];
    if (om_len > sizeof(buf)) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    int rc = ble_hs_mbuf_to_flat(ctxt->om, buf, om_len, NULL);
    if (rc != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    ESP_LOGI(TAG, "screen_data rx: %u bytes", om_len);
    if (s_callbacks.on_screen_data) {
        s_callbacks.on_screen_data(buf, om_len);
    }

    return 0;
}

static int prv_control_access(uint16_t conn_handle, uint16_t attr_handle,
                              struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    uint16_t om_len = OS_MBUF_PKTLEN(ctxt->om);
    uint8_t buf[16];
    if (om_len > sizeof(buf)) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    int rc = ble_hs_mbuf_to_flat(ctxt->om, buf, om_len, NULL);
    if (rc != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    if (s_callbacks.on_control) {
        s_callbacks.on_control(buf, om_len);
    }

    return 0;
}

static int prv_status_access(uint16_t conn_handle, uint16_t attr_handle,
                             struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;

    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        /* Return an empty payload for now; the status format is
         * defined in Slice 2 and will be wired up later. */
        return 0;
    }

    return BLE_ATT_ERR_UNLIKELY;
}

/* ----------------------------------------------------------------------- */
/* Static GATT table                                                        */
/* ----------------------------------------------------------------------- */

static const struct ble_gatt_chr_def s_chr_defs[] = {
    {
        /* screen_data: write + write-without-response */
        .uuid = &s_screen_data_uuid.u,
        .access_cb = prv_screen_data_access,
        .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP,
    },
    {
        /* control: write */
        .uuid = &s_control_uuid.u,
        .access_cb = prv_control_access,
        .flags = BLE_GATT_CHR_F_WRITE,
    },
    {
        /* status: notify + read */
        .uuid = &s_status_uuid.u,
        .access_cb = prv_status_access,
        .val_handle = &s_status_val_handle,
        .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
    },
    { 0 } /* sentinel */
};

static const struct ble_gatt_svc_def s_svc_defs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &s_svc_uuid.u,
        .characteristics = s_chr_defs,
    },
    { 0 } /* sentinel */
};

/* ----------------------------------------------------------------------- */
/* GAP event handler                                                        */
/* ----------------------------------------------------------------------- */

static int prv_gap_event(struct ble_gap_event *event, void *arg);

static int prv_gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;

    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        ESP_LOGI(TAG, "connect; status=%d handle=%d", event->connect.status,
                 event->connect.conn_handle);
        if (event->connect.status == 0) {
            s_connected = true;
            s_conn_handle = event->connect.conn_handle;
            if (s_callbacks.on_connection_change) {
                s_callbacks.on_connection_change(true);
            }
            /* If there's a stored bond with this peer, iOS will resume
             * encryption automatically and BLE_GAP_EVENT_ENC_CHANGE will
             * fire with status=0. If there's no stored bond, iOS will
             * initiate SMP pairing. Either way we start AMS/ANCS
             * discovery on enc_change, not here. */
        } else {
            /* Connection attempt failed — restart advertising. */
            ble_server_start_advertising();
        }
        break;

    case BLE_GAP_EVENT_ENC_CHANGE:
        ESP_LOGI(TAG, "enc change; status=%d handle=%d", event->enc_change.status,
                 event->enc_change.conn_handle);
        if (event->enc_change.status == 0) {
            /* Encryption is up — discover Apple Media Service and
             * Apple Notification Center Service exposed by iOS. */
            ams_client_start_for_connection(event->enc_change.conn_handle);
            ancs_client_start_for_connection(event->enc_change.conn_handle);
        }
        /* On failure we just log. The connection may get disconnected
         * by iOS but we do NOT clear the bond store — any stale-bond
         * issue has to be resolved by forgetting the device on iOS
         * exactly once, not by nuking the firmware state every time. */
        break;

    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "disconnect; reason=%d", event->disconnect.reason);
        s_connected = false;
        ams_client_handle_disconnect(event->disconnect.conn.conn_handle);
        ancs_client_handle_disconnect(event->disconnect.conn.conn_handle);
        if (s_callbacks.on_connection_change) {
            s_callbacks.on_connection_change(false);
        }
        /* Auto-restart advertising so the phone can reconnect. */
        ble_server_start_advertising();
        break;

    case BLE_GAP_EVENT_NOTIFY_RX: {
        /* Notifications from iOS GATT services on the same connection
         * (AMS / ANCS). Dispatch to the matching client; if neither
         * recognises the attribute handle, drop it. */
        const uint8_t *body = event->notify_rx.om->om_data;
        uint16_t blen = event->notify_rx.om->om_len;
        if (ams_client_handle_notification(event->notify_rx.conn_handle,
                                           event->notify_rx.attr_handle, body, blen)) {
            break;
        }
        ancs_client_handle_notification(event->notify_rx.conn_handle, event->notify_rx.attr_handle,
                                        body, blen);
        break;
    }

    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "mtu update; conn=%d mtu=%d", event->mtu.conn_handle, event->mtu.value);
        break;

    case BLE_GAP_EVENT_SUBSCRIBE:
        ESP_LOGI(TAG, "subscribe; conn=%d attr=%d", event->subscribe.conn_handle,
                 event->subscribe.attr_handle);
        break;

    default:
        break;
    }

    return 0;
}

/* ----------------------------------------------------------------------- */
/* NimBLE host reset/sync callbacks                                         */
/* ----------------------------------------------------------------------- */

static void prv_on_reset(int reason)
{
    ESP_LOGE(TAG, "nimble host reset; reason=%d", reason);
}

static void prv_on_sync(void)
{
    ESP_LOGI(TAG, "nimble host synced — starting advertising");
    /* Do NOT clear the bond store at boot. Doing so would break
     * autoconnect: iOS keeps its stored bond even across our reflashes,
     * and would then fail to encrypt when reconnecting because we no
     * longer recognise it. Keeping the NimBLE store persistent preserves
     * the LTK symmetry. */
    ble_server_start_advertising();
}

static void prv_nimble_host_task(void *param)
{
    (void)param;
    ESP_LOGI(TAG, "nimble host task started");
    nimble_port_run(); /* blocks until nimble_port_stop() */
    nimble_port_freertos_deinit();
}

/* ----------------------------------------------------------------------- */
/* Public API                                                               */
/* ----------------------------------------------------------------------- */

int ble_server_init(const ble_server_callbacks_t *callbacks)
{
    if (callbacks) {
        s_callbacks = *callbacks;
    } else {
        memset(&s_callbacks, 0, sizeof(s_callbacks));
    }

    int rc;

    /* nimble_port_init() initialises the NimBLE stack. In ESP-IDF v5.3
     * this returns esp_err_t (ESP_OK = 0 on success). */
    rc = nimble_port_init();
    if (rc != 0) {
        ESP_LOGE(TAG, "nimble_port_init failed: %d", rc);
        return -1;
    }

    /* Register host callbacks. */
    ble_hs_cfg.reset_cb = prv_on_reset;
    ble_hs_cfg.sync_cb = prv_on_sync;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;

    /* Enable LE Secure Connections + bonding so we can access AMS (music)
     * and ANCS (calls) on iOS. The bond is stored in NVS and persists
     * across reflashes — we NEVER call ble_store_clear() or erase NVS
     * from code. The user pairs ONCE via AccessorySetupKit and the
     * bond is stable from then on. */
    ble_hs_cfg.sm_io_cap = BLE_SM_IO_CAP_NO_IO;
    ble_hs_cfg.sm_bonding = 1;
    ble_hs_cfg.sm_sc = 1;
    ble_hs_cfg.sm_mitm = 0;
    ble_hs_cfg.sm_our_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.sm_their_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;

    /* Register GATT services. ble_svc_gap_init() must run before
     * ble_svc_gap_device_name_set() so the GAP service exists first and
     * the name set call targets the right attribute. */
    ble_svc_gap_init();
    ble_svc_gatt_init();

    /* Set device name. */
    ble_svc_gap_device_name_set("ScramScreen");

    rc = ble_gatts_count_cfg(s_svc_defs);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_count_cfg failed: %d", rc);
        return -2;
    }

    rc = ble_gatts_add_svcs(s_svc_defs);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_add_svcs failed: %d", rc);
        return -3;
    }

    /* Start the NimBLE host task. */
    nimble_port_freertos_init(prv_nimble_host_task);

    return 0;
}

int ble_server_start_advertising(void)
{
    struct ble_gap_adv_params adv_params = { 0 };
    struct ble_hs_adv_fields fields = { 0 };
    struct ble_hs_adv_fields rsp_fields = { 0 };

    /* Advertising packet (31-byte limit):
     *   Flags:           3 bytes
     *   128-bit UUID:   18 bytes  (required in primary adv for AccessorySetupKit)
     *   Short name:      7 bytes  ("Scram" — 2 header + 5 chars)
     *   Total:          28 bytes
     *
     * The full name "ScramScreen" goes in the scan response. */
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;

    fields.uuids128 = (ble_uuid128_t *)&s_svc_uuid;
    fields.num_uuids128 = 1;
    fields.uuids128_is_complete = 1;

    /* Shortened name in primary adv (name_is_complete = 0). */
    static const char short_name[] = "Scram";
    fields.name = (uint8_t *)short_name;
    fields.name_len = sizeof(short_name) - 1;
    fields.name_is_complete = 0;

    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gap_adv_set_fields failed: %d", rc);
        return rc;
    }

    /* Scan response: complete device name. */
    const char *name = ble_svc_gap_device_name();
    rsp_fields.name = (uint8_t *)name;
    rsp_fields.name_len = (uint8_t)strlen(name);
    rsp_fields.name_is_complete = 1;

    rc = ble_gap_adv_rsp_set_fields(&rsp_fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gap_adv_rsp_set_fields failed: %d", rc);
        return rc;
    }

    /* Connectable, undirected advertising. */
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;

    rc = ble_gap_adv_start(BLE_OWN_ADDR_PUBLIC, NULL, BLE_HS_FOREVER, &adv_params, prv_gap_event,
                           NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gap_adv_start failed: %d", rc);
        return rc;
    }

    ESP_LOGI(TAG, "advertising started");
    return 0;
}

int ble_server_stop_advertising(void)
{
    int rc = ble_gap_adv_stop();
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gap_adv_stop failed: %d", rc);
    }
    return rc;
}

int ble_server_notify_status(const uint8_t *data, size_t len)
{
    if (!s_connected) {
        return -1;
    }

    struct os_mbuf *om = ble_hs_mbuf_from_flat(data, (uint16_t)len);
    if (!om) {
        return -2;
    }

    int rc = ble_gatts_notify_custom(s_conn_handle, s_status_val_handle, om);
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gatts_notify_custom failed: %d", rc);
    }
    return rc;
}

bool ble_server_is_connected(void)
{
    return s_connected;
}
