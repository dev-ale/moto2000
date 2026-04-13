idf_component_register(
    SRCS "src/ota_receiver.c"
    INCLUDE_DIRS "include"
    REQUIRES app_update esp_partition esp_system mbedtls log freertos
)
