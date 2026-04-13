idf_component_register(
    SRCS "src/ota_https.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_https_ota esp_http_client esp-tls app_update log freertos wifi_manager
)
