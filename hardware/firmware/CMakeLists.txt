# ScramScreen firmware — ESP-IDF project
# Target: Waveshare ESP32-S3 1.75" AMOLED Round Display
# Required ESP-IDF version: v5.3+

cmake_minimum_required(VERSION 3.16)

set(SUPPORTED_TARGETS esp32s3)

# Project version — exposed at runtime via esp_app_get_description()->version
# and reported to iOS over the BLE status characteristic so the More tab
# can show the current firmware revision and decide when OTA is needed.
set(PROJECT_VER "0.1.1")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(scramscreen)
