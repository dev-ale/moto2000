# ScramScreen firmware — ESP-IDF project
# Target: Waveshare ESP32-S3 1.75" AMOLED Round Display
# Required ESP-IDF version: v5.3+

cmake_minimum_required(VERSION 3.16)

set(SUPPORTED_TARGETS esp32s3)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(scramscreen)
