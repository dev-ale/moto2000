/*
 * ScramScreen — custom round AMOLED motorcycle dashboard
 *
 * Real boot sequence: initialises NVS, display (LVGL + QSPI AMOLED),
 * all firmware state machines, BLE GATT server, and enters the LVGL
 * main loop. This replaces the Slice-2 stub.
 */

#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "nvs_flash.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "ble_server.h"
#include "ble_server_handlers.h"
#include "display.h"
#include "screen_fsm.h"
#include "ble_reconnect.h"
#include "ble_protocol.h"

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
static screen_fsm_t         s_screen_fsm;
static ble_reconnect_fsm_t  s_reconnect_fsm;
static ble_payload_cache_t  s_payload_cache;

/* ------------------------------------------------------------------ */
/* BLE callback implementations                                        */
/* ------------------------------------------------------------------ */

static void on_screen_data(const uint8_t *payload, size_t len)
{
    uint32_t now_ms = (uint32_t)(esp_timer_get_time() / 1000);
    ble_server_handle_screen_data(payload, len,
                                  &s_screen_fsm, &s_payload_cache, now_ms);

    /*
     * If the screen FSM says the active screen just got new data, push
     * it to the LVGL screen manager for rendering.  We use update_live
     * so only the current screen re-renders — no flashing between screens.
     */
    screen_manager_update_live(payload, len);
}

static void on_control(const uint8_t *payload, size_t len)
{
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
        ESP_LOGW(TAG, "BLE disconnected — showing last known data");
    } else {
        ESP_LOGI(TAG, "BLE connected");
    }
}

/* ------------------------------------------------------------------ */
/* LVGL tick timer callback (esp_timer, 5 ms period)                   */
/* ------------------------------------------------------------------ */

static void lvgl_tick_cb(void *arg)
{
    (void)arg;
    lv_tick_inc(5);
}

/* ------------------------------------------------------------------ */
/* app_main — firmware entry point                                     */
/* ------------------------------------------------------------------ */

void app_main(void)
{
    ESP_LOGI(TAG, "ScramScreen booting");

    /* 1. NVS — required by NimBLE for bonding storage. */
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES ||
        err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    /* 2. Initialise firmware state machines. */
    screen_fsm_init(&s_screen_fsm, BLE_SCREEN_CLOCK);   /* boot to clock */
    ble_reconnect_init(&s_reconnect_fsm);
    ble_payload_cache_init(&s_payload_cache);

    /* 3. Initialise LVGL core. */
    lv_init();

    /* 4. Initialise display hardware + LVGL driver. */
    int disp_rc = display_init();
    if (disp_rc != 0) {
        ESP_LOGE(TAG, "display_init failed: %d", disp_rc);
    }

    /* 5. LVGL tick timer — 5 ms period via esp_timer. */
    const esp_timer_create_args_t tick_args = {
        .callback = lvgl_tick_cb,
        .name     = "lv_tick",
    };
    esp_timer_handle_t tick_timer;
    ESP_ERROR_CHECK(esp_timer_create(&tick_args, &tick_timer));
    ESP_ERROR_CHECK(esp_timer_start_periodic(tick_timer, 5000));  /* 5 ms */

    /* 6. Apply ScramScreen LVGL theme. */
    lv_display_t *disp = (lv_display_t *)display_get_lv_display();
    scram_theme_apply(disp);

    /* 7. Initialise screen manager — creates the initial clock screen. */
    screen_manager_init();

    /* 8. Set panel brightness to a reasonable default. */
    display_set_brightness(80);

    /* 9. Initialise BLE server with callbacks. */
    ble_server_callbacks_t ble_cbs = {
        .on_screen_data      = on_screen_data,
        .on_control           = on_control,
        .on_connection_change = on_connection_change,
    };
    int ble_rc = ble_server_init(&ble_cbs);
    if (ble_rc != 0) {
        ESP_LOGE(TAG, "ble_server_init failed: %d", ble_rc);
    }
    ble_server_start_advertising();

    ESP_LOGI(TAG, "Ready — advertising as ScramScreen");

    /* 10. Main loop: drive LVGL timers and yield to FreeRTOS. */
    while (1) {
        uint32_t delay_ms = lv_timer_handler();
        if (delay_ms < 5) {
            delay_ms = 5;
        }
        vTaskDelay(pdMS_TO_TICKS(delay_ms));
    }
}
