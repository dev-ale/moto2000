/*
 * stb_impl.c — compilation unit for stb single-header libraries.
 *
 * stb_image.h (PNG/JPEG/... decoder) and stb_image_write.h (PNG encoder)
 * are both header-only libraries distributed under the public domain.
 * We pin the stb commit in the top-level CMakeLists.txt via FetchContent
 * for reproducibility.
 */
#define STB_IMAGE_IMPLEMENTATION
/* stb uses #ifdef STBI_NO_STDIO, so defining the macro at all — even to
 * 0 — disables the stdio-based loader. Leave it undefined so that
 * stbi_load(const char *) is compiled in for the snapshot-diff tool. */
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"
