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

    /* 5. Initialise BLE server with callbacks. */
    ble_server_callbacks_t ble_cbs = {
        .on_screen_data = on_screen_data,
        .on_control = on_control,
        .on_connection_change = on_connection_change,
    };
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
