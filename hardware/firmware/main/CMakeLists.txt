idf_component_register(
    SRCS "scramscreen_main.c"
    INCLUDE_DIRS "."
    REQUIRES
        esp_common
        log
        nvs_flash
)
