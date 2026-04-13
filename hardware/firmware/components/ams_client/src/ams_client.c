/*
 * ams_client.c — NimBLE GATT client wrapper for the Apple Media Service.
 *
 * Discovery sequence after a connection comes up:
 *   1. ble_gattc_disc_svc_by_uuid(AMS_SERVICE)
 *   2. ble_gattc_disc_all_chrs() to find Entity Update + Remote Command
 *   3. ble_gattc_disc_all_dscs() on Entity Update to find its CCCD
 *   4. Write 0x0001 to CCCD to enable notifications
 *   5. Write the entity/attribute filter to Entity Update so iOS knows
 *      which fields to push
 *
 * Notifications then arrive via BLE_GAP_EVENT_NOTIFY_RX in the GAP
 * event handler. The caller forwards them to ams_client_handle_notification()
 * which decodes them through the pure-C parser and emits a music payload
 * via the registered callback.
 */
#include "ams_client.h"
#include "ams_parser.h"

#include <string.h>

#include "esp_log.h"
#include "esp_timer.h"
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_uuid.h"

#define TAG "ams_client"

/* Apple Media Service UUIDs in little-endian byte order. */
static const ble_uuid128_t AMS_SERVICE = BLE_UUID128_INIT(
    0xDC, 0xF8, 0x55, 0xAD, 0x02, 0xC5, 0xF4, 0x8E, 0x3A, 0x43, 0x36, 0x0F, 0x2B, 0x50, 0xD3, 0x89);

static const ble_uuid128_t AMS_REMOTE_COMMAND = BLE_UUID128_INIT(
    0xC2, 0x51, 0xCA, 0xF7, 0x56, 0x0E, 0xDF, 0xB8, 0x8A, 0x4A, 0xB1, 0x57, 0xD8, 0x81, 0x3C, 0x9B);

static const ble_uuid128_t AMS_ENTITY_UPDATE = BLE_UUID128_INIT(
    0x02, 0xC1, 0x96, 0xBA, 0x92, 0xBB, 0x0C, 0x9A, 0x1F, 0x41, 0x8D, 0x80, 0xCE, 0xAB, 0x7C, 0x2F);

/* Per-connection state. ScramScreen only ever supports one phone, so a
 * single static slot is fine. */
static struct {
    bool in_use;
    uint16_t conn_handle;
    uint16_t svc_start_handle;
    uint16_t svc_end_handle;
    uint16_t entity_update_handle;
    uint16_t remote_command_handle;
    bool notifications_enabled;
    ams_state_t state;
} s_ctx;

static ams_client_track_cb_t s_on_track_update;
static esp_timer_handle_t s_progress_timer;

/* Forward decl. */
static void emit_state(void);

/* Advance the cached playback position by one second every tick while
 * playing. iOS only pushes Player/PlaybackInfo on state change — we
 * extrapolate client-side so the progress bar animates smoothly. */
static void progress_tick_cb(void *arg)
{
    (void)arg;
    if (!s_ctx.in_use) {
        return;
    }
    if (!s_ctx.state.is_playing) {
        return;
    }
    if (s_ctx.state.position_seconds == 0xFFFFu) {
        return;
    }
    if (s_ctx.state.duration_seconds != 0xFFFFu &&
        s_ctx.state.position_seconds + 1 >= s_ctx.state.duration_seconds) {
        return;
    }
    s_ctx.state.position_seconds++;
    emit_state();
}

/* Encode the current AMS state as a ble_music_data_t and dispatch via
 * the registered callback. Called whenever the state changes. */
static void emit_state(void)
{
    if (!s_on_track_update) {
        return;
    }
    ble_music_data_t data = {
        .music_flags = (uint8_t)(s_ctx.state.is_playing ? BLE_MUSIC_FLAG_PLAYING : 0),
        .position_seconds = s_ctx.state.position_seconds,
        .duration_seconds = s_ctx.state.duration_seconds,
    };
    /* Field-by-field copy because struct fields are fixed-size char arrays. */
    snprintf(data.title, sizeof(data.title), "%s", s_ctx.state.title);
    snprintf(data.artist, sizeof(data.artist), "%s", s_ctx.state.artist);
    snprintf(data.album, sizeof(data.album), "%s", s_ctx.state.album);
    s_on_track_update(&data);
}

/* ----------------------------------------------------------------------- */
/* GATT discovery callbacks (forward declarations + implementations).      */
/* ----------------------------------------------------------------------- */

static int on_chr_discovered(uint16_t conn_handle, const struct ble_gatt_error *error,
                             const struct ble_gatt_chr *chr, void *arg);
static int on_svc_discovered(uint16_t conn_handle, const struct ble_gatt_error *error,
                             const struct ble_gatt_svc *svc, void *arg);

/* Each filter write REPLACES the previous filter on iOS side. To get
 * updates for multiple entities (Player + Track), we need to write
 * multiple filters; iOS will push notifications for all active filters.
 * Writing both filters in quick succession means iOS retains the LAST
 * one — so we have to combine or write serially with a state machine.
 *
 * Apple's spec allows one filter per entity, so we write Track first
 * (needed immediately for title/artist) and follow up with Player
 * (for play-state + elapsed) after a short delay in on_filter_written. */

static int on_player_filter_written(uint16_t conn_handle, const struct ble_gatt_error *error,
                                    struct ble_gatt_attr *attr, void *arg)
{
    (void)conn_handle;
    (void)attr;
    (void)arg;
    if (error->status != 0) {
        ESP_LOGW(TAG, "AMS player filter write failed: status=%d", error->status);
    } else {
        ESP_LOGI(TAG, "AMS player filter write ok");
    }
    return 0;
}

static int on_track_filter_written(uint16_t conn_handle, const struct ble_gatt_error *error,
                                   struct ble_gatt_attr *attr, void *arg)
{
    (void)attr;
    (void)arg;
    if (error->status != 0) {
        ESP_LOGW(TAG, "AMS track filter write failed: status=%d (continuing)", error->status);
        /* iOS appears to push Track notifications anyway without an
         * explicit filter — so we still want to register the Player
         * filter to get PlaybackInfo (play state + elapsed). */
    } else {
        ESP_LOGI(TAG, "AMS track filter write ok");
    }
    ESP_LOGI(TAG, "writing AMS player filter to handle %d", s_ctx.entity_update_handle);
    static const uint8_t player_filter[] = {
        AMS_ENTITY_PLAYER,
        AMS_PLAYER_PLAYBACK_INFO,
    };
    int rc = ble_gattc_write_flat(conn_handle, s_ctx.entity_update_handle, player_filter,
                                  sizeof(player_filter), on_player_filter_written, NULL);
    if (rc != 0) {
        ESP_LOGW(TAG, "AMS player filter dispatch failed: rc=%d", rc);
    }
    return 0;
}

static void write_entity_update_filters(uint16_t conn_handle)
{
    static const uint8_t track_filter[] = {
        AMS_ENTITY_TRACK, AMS_TRACK_ARTIST, AMS_TRACK_ALBUM, AMS_TRACK_TITLE, AMS_TRACK_DURATION,
    };
    ESP_LOGI(TAG, "writing AMS track filter to handle %d", s_ctx.entity_update_handle);
    int rc = ble_gattc_write_flat(conn_handle, s_ctx.entity_update_handle, track_filter,
                                  sizeof(track_filter), on_track_filter_written, NULL);
    if (rc != 0) {
        ESP_LOGW(TAG, "AMS track filter dispatch failed: rc=%d", rc);
    }
}

static int on_cccd_written(uint16_t conn_handle, const struct ble_gatt_error *error,
                           struct ble_gatt_attr *attr, void *arg)
{
    (void)attr;
    if (error->status != 0) {
        ESP_LOGW(TAG, "CCCD write failed: status=%d", error->status);
        return 0;
    }
    s_ctx.notifications_enabled = true;
    ESP_LOGI(TAG, "AMS notifications enabled, writing entity filters");
    write_entity_update_filters(conn_handle);
    return 0;
}

/* Descriptor discovery callback. We scope the descriptor scan to a
 * narrow range right after the characteristic value so we're guaranteed
 * to only see descriptors belonging to Entity Update. Per Apple's AMS
 * spec the CCCD is the first descriptor with UUID 0x2902. */
static int on_entity_update_dsc_discovered(uint16_t conn_handle, const struct ble_gatt_error *error,
                                           uint16_t chr_val_handle, const struct ble_gatt_dsc *dsc,
                                           void *arg)
{
    (void)chr_val_handle;
    (void)arg;
    if (error->status == BLE_HS_EDONE) {
        ESP_LOGI(TAG, "Entity Update descriptor discovery done");
        return 0;
    }
    if (error->status != 0 || dsc == NULL) {
        ESP_LOGW(TAG, "Entity Update dsc discovery error: status=%d", error->status);
        return 0;
    }
    ESP_LOGI(TAG, "AMS descriptor at handle %d", dsc->handle);
    if (ble_uuid_cmp(&dsc->uuid.u, BLE_UUID16_DECLARE(BLE_GATT_DSC_CLT_CFG_UUID16)) == 0) {
        ESP_LOGI(TAG, "AMS Entity Update CCCD at handle %d", dsc->handle);
        const uint8_t cccd_val[2] = { 0x01, 0x00 };
        int rc = ble_gattc_write_flat(conn_handle, dsc->handle, cccd_val, sizeof(cccd_val),
                                      on_cccd_written, NULL);
        if (rc != 0) {
            ESP_LOGW(TAG, "CCCD write dispatch failed: rc=%d", rc);
        }
    }
    return 0;
}

/* State for the serialised CCCD probe below. */
static uint16_t s_probe_next_handle;
static uint16_t s_probe_last_handle;

static int probe_step(uint16_t conn_handle);

/* Write callback for the serialised CCCD probe. */
static int on_probe_write(uint16_t conn_handle, const struct ble_gatt_error *error,
                          struct ble_gatt_attr *attr, void *arg)
{
    (void)arg;
    uint16_t attempted = attr ? attr->handle : 0;
    if (error->status == 0) {
        ESP_LOGI(TAG, "AMS CCCD probe: handle %d ACCEPTED", attempted);
        s_ctx.notifications_enabled = true;
        write_entity_update_filters(conn_handle);
        return 0;
    }
    ESP_LOGI(TAG, "AMS CCCD probe: handle %d rejected (status=%d)", attempted, error->status);
    /* Advance to the next candidate handle. */
    probe_step(conn_handle);
    return 0;
}

static int probe_step(uint16_t conn_handle)
{
    if (s_probe_next_handle > s_probe_last_handle) {
        ESP_LOGW(TAG, "AMS CCCD probe exhausted — no handle accepted");
        return 0;
    }
    uint16_t h = s_probe_next_handle++;
    const uint8_t cccd_val[2] = { 0x01, 0x00 };
    int rc = ble_gattc_write_flat(conn_handle, h, cccd_val, sizeof(cccd_val), on_probe_write, NULL);
    if (rc != 0) {
        ESP_LOGW(TAG, "AMS CCCD probe dispatch at %d failed: rc=%d", h, rc);
        /* Try the next handle on dispatch failure too. */
        return probe_step(conn_handle);
    }
    return 0;
}

static void enable_entity_update_notifications(uint16_t conn_handle)
{
    /* NimBLE's ble_gattc_disc_all_dscs returns zero descriptors when
     * querying Apple's AMS service — iOS either hides them or the
     * Find Information response is empty. Brute-force the CCCD by
     * writing 0x0001 to each handle in the narrow range following the
     * Entity Update value. We walk sequentially (not in parallel) to
     * avoid filling the NimBLE command queue. */
    s_probe_next_handle = (uint16_t)(s_ctx.entity_update_handle + 1);
    s_probe_last_handle = (uint16_t)(s_ctx.entity_update_handle + 4);
    if (s_probe_last_handle > s_ctx.svc_end_handle) {
        s_probe_last_handle = s_ctx.svc_end_handle;
    }
    ESP_LOGI(TAG, "AMS CCCD probe: walking handles %d..%d serially", s_probe_next_handle,
             s_probe_last_handle);
    probe_step(conn_handle);
}

static int on_chr_discovered(uint16_t conn_handle, const struct ble_gatt_error *error,
                             const struct ble_gatt_chr *chr, void *arg)
{
    (void)arg;
    if (error->status != 0 || chr == NULL) {
        /* Discovery complete — if we have Entity Update, subscribe. */
        if (s_ctx.entity_update_handle != 0) {
            enable_entity_update_notifications(conn_handle);
        }
        return 0;
    }
    if (ble_uuid_cmp(&chr->uuid.u, &AMS_ENTITY_UPDATE.u) == 0) {
        s_ctx.entity_update_handle = chr->val_handle;
        ESP_LOGI(TAG, "AMS Entity Update at handle %d", chr->val_handle);
    } else if (ble_uuid_cmp(&chr->uuid.u, &AMS_REMOTE_COMMAND.u) == 0) {
        s_ctx.remote_command_handle = chr->val_handle;
    }
    return 0;
}

static int on_svc_discovered(uint16_t conn_handle, const struct ble_gatt_error *error,
                             const struct ble_gatt_svc *svc, void *arg)
{
    (void)arg;
    if (error->status != 0 || svc == NULL) {
        if (error->status == BLE_HS_EDONE) {
            ESP_LOGI(TAG, "AMS service discovery complete");
        } else if (svc == NULL) {
            ESP_LOGW(TAG, "AMS service not found on iPhone");
        }
        return 0;
    }
    s_ctx.svc_start_handle = svc->start_handle;
    s_ctx.svc_end_handle = svc->end_handle;
    ESP_LOGI(TAG, "AMS service handles %d..%d", svc->start_handle, svc->end_handle);
    ble_gattc_disc_all_chrs(conn_handle, svc->start_handle, svc->end_handle, on_chr_discovered,
                            NULL);
    return 0;
}

/* ----------------------------------------------------------------------- */
/* Public API                                                               */
/* ----------------------------------------------------------------------- */

void ams_client_init(ams_client_track_cb_t on_track_update)
{
    s_on_track_update = on_track_update;
    memset(&s_ctx, 0, sizeof(s_ctx));
    ams_state_init(&s_ctx.state);

    if (s_progress_timer == NULL) {
        const esp_timer_create_args_t args = {
            .callback = progress_tick_cb,
            .name = "ams_prog",
        };
        if (esp_timer_create(&args, &s_progress_timer) == ESP_OK) {
            esp_timer_start_periodic(s_progress_timer, 1 * 1000 * 1000);
        }
    }
}

void ams_client_start_for_connection(uint16_t conn_handle)
{
    memset(&s_ctx, 0, sizeof(s_ctx));
    ams_state_init(&s_ctx.state);
    s_ctx.in_use = true;
    s_ctx.conn_handle = conn_handle;

    int rc = ble_gattc_disc_svc_by_uuid(conn_handle, &AMS_SERVICE.u, on_svc_discovered, NULL);
    if (rc != 0) {
        ESP_LOGW(TAG, "ble_gattc_disc_svc_by_uuid failed: rc=%d", rc);
    }
}

void ams_client_handle_disconnect(uint16_t conn_handle)
{
    if (s_ctx.in_use && s_ctx.conn_handle == conn_handle) {
        memset(&s_ctx, 0, sizeof(s_ctx));
        ams_state_init(&s_ctx.state);
    }
}

bool ams_client_handle_notification(uint16_t conn_handle, uint16_t attr_handle, const uint8_t *data,
                                    size_t len)
{
    if (!s_ctx.in_use || s_ctx.conn_handle != conn_handle) {
        return false;
    }
    ESP_LOGI(TAG, "notify rx attr=%d len=%d eu=%d", attr_handle, (int)len,
             s_ctx.entity_update_handle);
    /* Accept notifications on the Entity Update handle AND on its
     * "probe-found" CCCD neighbour (val_handle + 3 etc.) since NimBLE's
     * reported val_handle may not match the actual notify attribute on
     * Apple's AMS. */
    if (attr_handle != s_ctx.entity_update_handle &&
        attr_handle != (uint16_t)(s_ctx.entity_update_handle + 3)) {
        return false;
    }
    if (len >= 3) {
        ESP_LOGI(TAG, "  entity=%d attr=%d flags=0x%02x", data[0], data[1], data[2]);
    }
    if (ams_apply_entity_update(&s_ctx.state, data, len)) {
        ESP_LOGI(TAG, "  state: '%s' / '%s' playing=%d pos=%d dur=%d", s_ctx.state.title,
                 s_ctx.state.artist, s_ctx.state.is_playing, s_ctx.state.position_seconds,
                 s_ctx.state.duration_seconds);
        emit_state();
    }
    return true;
}
