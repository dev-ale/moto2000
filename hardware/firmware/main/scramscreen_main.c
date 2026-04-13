/*
 * ScramScreen — custom round AMOLED motorcycle dashboard
 *
 * Boot sequence: NVS → display (Waveshare BSP handles LVGL + QSPI) →
 * firmware state machines → BLE GATT server.
 *
 * The Waveshare BSP owns the LVGL task, tick timer, and display flush.
 * We must call bsp_display_lock()/bsp_display_unlock() around any
 * LVGL API calls.
 */

#include "esp_app_desc.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "nvs_flash.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#include "bsp/esp-bsp.h"

/* GPIO0 = BOOT button on the Waveshare ESP32-S3 1.75" AMOLED board.
 * Pressed = LOW (active low). */
#define BUTTON_GPIO GPIO_NUM_0

#include "ble_server.h"
#include "ble_server_handlers.h"
#include "display.h"
#include "screen_fsm.h"
#include "ble_reconnect.h"
#include "ble_protocol.h"
#include "ams_client.h"
#include "ancs_client.h"
#include "ota_receiver.h"

/* Screen includes — compiled from lvgl-sim/ into the ESP-IDF firmware. */
#include "screens/screen_clock.h"
#include "screens/screen_speed.h"
#include "screens/screen_compass.h"
#include "screens/screen_navigation.h"
#include "screens/screen_weather.h"
#include "screens/screen_music.h"
#include "screens/screen_trip_stats.h"
#include "screens/screen_lean_angle.h"
#include "screens/screen_altitude.h"
#include "screens/screen_calendar.h"
#include "screens/screen_fuel.h"
#include "screens/screen_call.h"
#include "screens/screen_blitzer.h"
#include "screens/screen_placeholder.h"

#include "common/screen_manager.h"
#include "theme/scram_theme.h"

static const char *TAG = "scramscreen";

/* Firmware state — file-scoped, shared across BLE callbacks. */
static screen_fsm_t s_screen_fsm;
static ble_reconnect_fsm_t s_reconnect_fsm;
static ble_payload_cache_t s_payload_cache;

/* ------------------------------------------------------------------ */
/* Boot / "waiting for connection" screen                              */
/* ------------------------------------------------------------------ */

/* ------------------------------------------------------------------ */
/* OTA progress screen — drawn while iOS is streaming a firmware      */
/* image. Rebuilds the active LVGL screen in place under the BSP      */
/* display lock so it doesn't race with the LVGL render task.         */
/* ------------------------------------------------------------------ */

static void render_ota_screen(ota_rx_state_t state, uint32_t bytes, uint32_t total)
{
    if (bsp_display_lock(UINT32_MAX) != ESP_OK) {
        return;
    }
    lv_obj_t *scr = lv_screen_active();
    lv_obj_clean(scr);
    lv_obj_set_style_bg_color(scr, lv_color_hex(0x0a0a0a), 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);

    lv_obj_t *title = lv_label_create(scr);
    lv_label_set_text(title, "Updating Firmware");
    lv_obj_set_style_text_color(title, lv_color_hex(0xF5A623), 0);
    lv_obj_set_style_text_font(title, &lv_font_montserrat_24, 0);
    lv_obj_align(title, LV_ALIGN_TOP_MID, 0, 130);

    int pct = (total > 0) ? (int)((uint64_t)bytes * 100 / total) : 0;

    char status[40];
    switch (state) {
    case OTA_RX_RECEIVING:
        snprintf(status, sizeof(status), "Receiving... %d%%", pct);
        break;
    case OTA_RX_VERIFYING:
        snprintf(status, sizeof(status), "Verifying...");
        break;
    case OTA_RX_DONE:
        snprintf(status, sizeof(status), "Restarting...");
        break;
    case OTA_RX_FAILED:
        snprintf(status, sizeof(status), "Update failed");
        break;
    default:
        snprintf(status, sizeof(status), "Preparing...");
        break;
    }

    lv_obj_t *lbl_status = lv_label_create(scr);
    lv_label_set_text(lbl_status, status);
    lv_obj_set_style_text_color(lbl_status, lv_color_hex(0xFFFFFF), 0);
    lv_obj_set_style_text_font(lbl_status, &lv_font_montserrat_28, 0);
    lv_obj_align(lbl_status, LV_ALIGN_CENTER, 0, 0);

    /* Bar — 320 px wide track + green fill clamped to pct. */
    lv_obj_t *track = lv_obj_create(scr);
    lv_obj_set_size(track, 320, 16);
    lv_obj_set_style_radius(track, 8, 0);
    lv_obj_set_style_bg_color(track, lv_color_hex(0x222222), 0);
    lv_obj_set_style_border_width(track, 0, 0);
    lv_obj_clear_flag(track, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(track, LV_ALIGN_CENTER, 0, 60);

    int fill_w = (pct * 320) / 100;
    if (fill_w < 4)
        fill_w = 4;
    lv_obj_t *fill = lv_obj_create(track);
    lv_obj_set_size(fill, fill_w, 16);
    lv_obj_set_style_radius(fill, 8, 0);
    lv_obj_set_style_bg_color(fill, lv_color_hex(0xF5A623), 0);
    lv_obj_set_style_border_width(fill, 0, 0);
    lv_obj_clear_flag(fill, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_align(fill, LV_ALIGN_LEFT_MID, 0, 0);

    char bytes_buf[32];
    snprintf(bytes_buf, sizeof(bytes_buf), "%lu / %lu KB", (unsigned long)(bytes / 1024),
             (unsigned long)(total / 1024));
    lv_obj_t *lbl_bytes = lv_label_create(scr);
    lv_label_set_text(lbl_bytes, bytes_buf);
    lv_obj_set_style_text_color(lbl_bytes, lv_color_hex(0x666666), 0);
    lv_obj_set_style_text_font(lbl_bytes, &lv_font_montserrat_16, 0);
    lv_obj_align(lbl_bytes, LV_ALIGN_CENTER, 0, 100);

    bsp_display_unlock();
}

static void on_ota_progress(ota_rx_state_t state, uint32_t bytes, uint32_t total)
{
    /* Throttle: only redraw on every 4th chunk while receiving so we
     * don't flood the LVGL task with rebuilds. Always redraw on state
     * transitions. */
    static uint32_t last_drawn = 0;
    static ota_rx_state_t last_state = OTA_RX_IDLE;
    if (state == OTA_RX_RECEIVING && state == last_state && (bytes - last_drawn) < (240 * 8)) {
        return;
    }
    last_drawn = bytes;
    last_state = state;
    render_ota_screen(state, bytes, total);
}

static void render_waiting_screen(void)
{
    if (bsp_display_lock(UINT32_MAX) != ESP_OK) {
        return;
    }
    /* Mutate the existing active screen in place — never create a new one
     * or call lv_screen_load. See screen_manager.c for the rationale. */
    lv_obj_t *scr = lv_screen_active();
    lv_obj_clean(scr);
    lv_obj_set_style_bg_color(scr, lv_color_hex(0x0a0a0a), 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);

    lv_obj_t *label = lv_label_create(scr);
    lv_label_set_text(label, "ScramScreen");
    lv_obj_set_style_text_color(label, lv_color_hex(0xF5A623), 0);
    lv_obj_set_style_text_font(label, &lv_font_montserrat_28, 0);
    lv_obj_center(label);

    lv_obj_t *sub = lv_label_create(scr);
    lv_label_set_text(sub, "Waiting for connection...");
    lv_obj_set_style_text_color(sub, lv_color_hex(0x666666), 0);
    lv_obj_set_style_text_font(sub, &lv_font_montserrat_16, 0);
    lv_obj_align(sub, LV_ALIGN_CENTER, 0, 40);

    bsp_display_unlock();
}

/* ------------------------------------------------------------------ */
/* Button task — polls GPIO0 for press, debounced.                    */
/*                                                                    */
/* Press cycles to the next cached screen via the unified screen      */
/* manager. Live iOS data is automatically rendered on whichever      */
/* screen the user navigated to.                                      */
/* ------------------------------------------------------------------ */

static void button_task(void *arg)
{
    (void)arg;
    bool last = true; /* released (pull-up) */
    while (1) {
        bool pressed = gpio_get_level(BUTTON_GPIO) == 0;
        if (pressed && last) {
            ESP_LOGI(TAG, "button → next screen");
            if (bsp_display_lock(UINT32_MAX) == ESP_OK) {
                screen_manager_next_screen();
                bsp_display_unlock();
            }
            /* Wait for release. */
            while (gpio_get_level(BUTTON_GPIO) == 0) {
                vTaskDelay(pdMS_TO_TICKS(20));
            }
            /* Cooldown so LVGL flushes the new screen before another press. */
            vTaskDelay(pdMS_TO_TICKS(300));
        }
        last = !pressed;
        vTaskDelay(pdMS_TO_TICKS(20));
    }
}

static void button_init(void)
{
    gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << BUTTON_GPIO,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&cfg);
    xTaskCreate(button_task, "btn", 4096, NULL, 5, NULL);
    ESP_LOGI(TAG, "button on GPIO%d ready", BUTTON_GPIO);
}

/* ------------------------------------------------------------------ */
/* BLE callback implementations                                        */
/* ------------------------------------------------------------------ */

static void on_screen_data(const uint8_t *payload, size_t len)
{
    uint32_t now_ms = (uint32_t)(esp_timer_get_time() / 1000);
    ble_server_handle_screen_data(payload, len, &s_screen_fsm, &s_payload_cache, now_ms);

    /*
     * Push to the LVGL screen manager for rendering.
     * Must hold BSP display lock around any LVGL calls.
     */
    if (bsp_display_lock(UINT32_MAX) == ESP_OK) {
        screen_manager_update_live(payload, len);
        bsp_display_unlock();
    }
}

static void on_control(const uint8_t *payload, size_t len)
{
    /* Decode here so we can act on commands the FSM doesn't handle —
     * specifically SET_BRIGHTNESS, which talks to the BSP. */
    ble_control_payload_t ctrl;
    if (ble_decode_control(payload, len, &ctrl) == BLE_OK &&
        ctrl.command == BLE_CONTROL_CMD_SET_BRIGHTNESS) {
        int pct = (int)ctrl.brightness;
        if (pct < 0)
            pct = 0;
        if (pct > 100)
            pct = 100;
        ESP_LOGI(TAG, "control: set brightness to %d%%", pct);
        bsp_display_brightness_set(pct);
    }

    ble_server_handle_control(payload, len, &s_screen_fsm);

    /*
     * If the control command switched the active screen, tell the screen
     * manager to handle the full payload (which triggers a screen load).
     * For sleep/wake we could dim/undim the display here, but
     * ble_server_handle_control already drives the FSM and the main loop
     * will pick up the state change.
     */
    if (s_screen_fsm.state == SCREEN_FSM_ACTIVE) {
        /* Retrieve cached payload for the new active screen and render. */
        const ble_payload_cache_entry_t *entry =
            ble_payload_cache_get(&s_payload_cache, s_screen_fsm.active_screen_id);
        if (entry && entry->present) {
            /* The cache stores only the body; screen_manager needs the
             * full BLE packet.  For now we trigger a re-render via the
             * screen manager's cache-aware path.  A future optimisation
             * could pass the body directly. */
        }
    }
}

static void on_connection_change(bool connected)
{
    uint32_t now_ms = (uint32_t)(esp_timer_get_time() / 1000);
    ble_server_handle_connection_change(connected, &s_reconnect_fsm, now_ms);

    if (!connected) {
        ESP_LOGW(TAG, "BLE disconnected — showing waiting screen");
        render_waiting_screen();
        return;
    }

    /* Don't render anything from this NimBLE-task callback. iOS will start
     * streaming screen payloads within ~1 s and screen_manager_update_live
     * will render them on the proper code path. Calling show_current from
     * here races with the LVGL task and crashes the renderer. */
    ESP_LOGI(TAG, "BLE connected — waiting for first iOS payload");
}

static void on_ota_data(const uint8_t *payload, size_t len)
{
    ota_receiver_handle_frame(payload, len);
}

/* Fired by ble_server when iOS enables notifications on the status
 * characteristic. This is the earliest moment iOS will actually receive
 * anything we notify, so we send the firmware version here. */
static void on_status_subscribed(void)
{
    const esp_app_desc_t *desc = esp_app_get_description();
    if (desc == NULL) {
        return;
    }
    unsigned maj = 0, min = 0, pat = 0;
    (void)sscanf(desc->version, "%u.%u.%u", &maj, &min, &pat);
    ble_status_payload_t status = {
        .type = BLE_STATUS_FIRMWARE_VERSION,
        .fw_major = (uint8_t)maj,
        .fw_minor = (uint8_t)min,
        .fw_patch = (uint8_t)pat,
    };
    uint8_t buf[8];
    size_t written = 0;
    if (ble_encode_status(&status, buf, sizeof(buf), &written) == BLE_OK) {
        ble_server_notify_status(buf, written);
        ESP_LOGI(TAG, "announced fw version %u.%u.%u", maj, min, pat);
    }
}

/* ------------------------------------------------------------------ */
/* AMS / ANCS callbacks — receive media + call updates from iOS over  */
/* the same BLE connection and feed them through the existing screen  */
/* manager pipeline. Both fire on the NimBLE host task, so we hold    */
/* the BSP display lock around screen_manager_update_live.            */
/* ------------------------------------------------------------------ */

static void on_music_update(const ble_music_data_t *music)
{
    if (!music) {
        return;
    }
    uint8_t buf[BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_MUSIC_BODY_SIZE];
    size_t written = 0;
    ble_result_t rc = ble_encode_music(music, 0, buf, sizeof(buf), &written);
    if (rc != BLE_OK) {
        ESP_LOGW(TAG, "music encode failed: %s", ble_result_name(rc));
        return;
    }
    if (bsp_display_lock(UINT32_MAX) == ESP_OK) {
        screen_manager_update_live(buf, written);
        bsp_display_unlock();
    }
}

static void on_call_event(const ble_incoming_call_data_t *call)
{
    if (!call) {
        return;
    }
    uint8_t buf[BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE];
    size_t written = 0;
    ble_result_t rc = ble_encode_incoming_call(call, 0, buf, sizeof(buf), &written);
    if (rc != BLE_OK) {
        ESP_LOGW(TAG, "incoming_call encode failed: %s", ble_result_name(rc));
        return;
    }
    if (bsp_display_lock(UINT32_MAX) == ESP_OK) {
        screen_manager_update_live(buf, written);
        bsp_display_unlock();
    }
}

/* ------------------------------------------------------------------ */
/* app_main — firmware entry point                                     */
/* ------------------------------------------------------------------ */

void app_main(void)
{
    ESP_LOGI(TAG, "ScramScreen booting");

    /* 1. NVS — required by NimBLE for bonding storage. */
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    /* 2. Initialise firmware state machines. */
    screen_fsm_init(&s_screen_fsm, BLE_SCREEN_CLOCK); /* boot to clock */
    ble_reconnect_init(&s_reconnect_fsm);
    ble_payload_cache_init(&s_payload_cache);

    /* 3. Initialise display hardware + LVGL via Waveshare BSP.
     *    bsp_display_start() handles: lv_init(), SPI bus, CO5300 panel,
     *    LVGL adapter with tick timer, PSRAM bounce buffers, and the
     *    LVGL task (FreeRTOS).  We must NOT call lv_init() or
     *    lv_timer_handler() ourselves. */
    int disp_rc = display_init();
    if (disp_rc != 0) {
        ESP_LOGE(TAG, "display_init failed: %d", disp_rc);
    }

    /* 4. Apply ScramScreen LVGL theme + initialise the screen manager.
     *    Seed every screen with a default-encoded placeholder so the user
     *    can cycle through all of them via the BOOT button even before iOS
     *    streams real data. iOS payloads then overwrite the placeholders. */
    if (bsp_display_lock(UINT32_MAX) == ESP_OK) {
        lv_display_t *disp = (lv_display_t *)display_get_lv_display();
        scram_theme_apply(disp);
        screen_manager_init();
        screen_manager_seed_placeholders();
        bsp_display_unlock();
    }

    /* Boot screen — replaced by the dashboard once BLE connects. */
    render_waiting_screen();

    /* 4b. Initialise the BOOT button (GPIO0) for screen cycling. */
    button_init();

    /* 5. Initialise the AMS / ANCS GATT clients with their callbacks.
     *    They start their discovery state machines on BLE_GAP_EVENT_CONNECT
     *    inside ble_server_init(). */
    ams_client_init(on_music_update);
    ancs_client_init(on_call_event);

    /* 6. Initialise BLE server with callbacks. */
    ble_server_callbacks_t ble_cbs = {
        .on_screen_data = on_screen_data,
        .on_control = on_control,
        .on_connection_change = on_connection_change,
        .on_ota_data = on_ota_data,
        .on_status_subscribed = on_status_subscribed,
    };
    ota_receiver_init();
    ota_receiver_set_progress_cb(on_ota_progress);
    int ble_rc = ble_server_init(&ble_cbs);
    if (ble_rc != 0) {
        ESP_LOGE(TAG, "ble_server_init failed: %d", ble_rc);
    }
    ble_server_start_advertising();

    ESP_LOGI(TAG, "Ready — advertising as ScramScreen");

    /* 6. Main task has nothing left to do — the BSP's LVGL task handles
     *    rendering, and BLE callbacks run in the NimBLE task.  Just
     *    keep the task alive (FreeRTOS deletes it if we return). */
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
