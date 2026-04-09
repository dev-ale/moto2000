/*
 * stb_impl.c — compilation unit for stb single-header libraries.
 *
 * stb_image.h (PNG/JPEG/... decoder) and stb_image_write.h (PNG encoder)
 * are both header-only libraries distributed under the public domain.
 * We pin the stb commit in the top-level CMakeLists.txt via FetchContent
 * for reproducibility.
 */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO 0
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
