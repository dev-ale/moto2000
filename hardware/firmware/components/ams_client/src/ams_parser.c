/*
 * ams_parser.c — Pure C parser for Apple Media Service notifications.
 *
 * See ams_parser.h for the wire format reference.
 */
#include "ams_parser.h"

#include <stdlib.h>
#include <string.h>

#define AMS_HEADER_SIZE 3 /* entity, attribute, flags */

void ams_state_init(ams_state_t *state)
{
    if (!state) {
        return;
    }
    memset(state, 0, sizeof(*state));
    state->duration_seconds = 0xFFFFu;
    state->position_seconds = 0xFFFFu;
    state->is_playing = false;
}

/* Copy a non-null-terminated UTF-8 source into a fixed-size buffer.
 * Truncates if needed and always writes a terminating NUL. */
static void copy_utf8_field(char *dst, size_t dst_cap, const uint8_t *src, size_t src_len)
{
    if (dst_cap == 0) {
        return;
    }
    size_t n = src_len < (dst_cap - 1) ? src_len : (dst_cap - 1);
    if (n > 0) {
        memcpy(dst, src, n);
    }
    dst[n] = '\0';
}

/* Parse a fixed-length numeric field from a non-null-terminated source.
 * Used for the Duration attribute, which arrives as an ASCII float
 * (e.g. "245.000000"). Returns 0xFFFF on parse failure. */
static uint16_t parse_uint16_seconds(const uint8_t *src, size_t src_len)
{
    /* Stack-bounded copy so we can call strtod. */
    char buf[32];
    if (src_len >= sizeof(buf)) {
        src_len = sizeof(buf) - 1;
    }
    memcpy(buf, src, src_len);
    buf[src_len] = '\0';

    char *end = NULL;
    double v = strtod(buf, &end);
    if (end == buf || v < 0.0 || v > (double)0xFFFEu) {
        return 0xFFFFu;
    }
    return (uint16_t)v;
}

/* Parse the PlaybackInfo string. Format is "state,rate,elapsed".
 *   state:    0 = paused, 1 = playing, 2 = rewinding, 3 = fast-forwarding
 *   rate:     ignored
 *   elapsed:  current playback position in seconds, ASCII float
 *
 * Updates is_playing and position_seconds in `state`. */
static void parse_playback_info(ams_state_t *state, const uint8_t *src, size_t src_len)
{
    /* Stack-bounded copy so we can use strtok-style splits. */
    char buf[64];
    if (src_len >= sizeof(buf)) {
        src_len = sizeof(buf) - 1;
    }
    memcpy(buf, src, src_len);
    buf[src_len] = '\0';

    char *first_comma = strchr(buf, ',');
    if (!first_comma) {
        return;
    }
    *first_comma = '\0';
    char *state_str = buf;
    char *rate_str = first_comma + 1;

    char *second_comma = strchr(rate_str, ',');
    char *elapsed_str = NULL;
    if (second_comma) {
        *second_comma = '\0';
        elapsed_str = second_comma + 1;
    }

    /* Parse state. */
    int playback_state = atoi(state_str);
    state->is_playing = (playback_state == 1);

    /* Parse elapsed (rate is intentionally ignored). */
    if (elapsed_str && *elapsed_str != '\0') {
        char *end = NULL;
        double v = strtod(elapsed_str, &end);
        if (end != elapsed_str && v >= 0.0 && v <= (double)0xFFFEu) {
            state->position_seconds = (uint16_t)v;
        }
    }
}

bool ams_apply_entity_update(ams_state_t *state, const uint8_t *data, size_t len)
{
    if (!state || !data || len < AMS_HEADER_SIZE) {
        return false;
    }
    uint8_t entity_id = data[0];
    uint8_t attribute_id = data[1];
    /* data[2] is the EntityUpdateFlags byte; bit 0 = truncated. We tolerate
     * truncation by simply storing whatever bytes arrived. */
    const uint8_t *value = data + AMS_HEADER_SIZE;
    size_t value_len = len - AMS_HEADER_SIZE;

    switch (entity_id) {
    case AMS_ENTITY_TRACK:
        switch (attribute_id) {
        case AMS_TRACK_ARTIST:
            copy_utf8_field(state->artist, sizeof(state->artist), value, value_len);
            return true;
        case AMS_TRACK_ALBUM:
            copy_utf8_field(state->album, sizeof(state->album), value, value_len);
            return true;
        case AMS_TRACK_TITLE:
            copy_utf8_field(state->title, sizeof(state->title), value, value_len);
            return true;
        case AMS_TRACK_DURATION:
            state->duration_seconds = parse_uint16_seconds(value, value_len);
            return true;
        default:
            return false;
        }

    case AMS_ENTITY_PLAYER:
        if (attribute_id == AMS_PLAYER_PLAYBACK_INFO) {
            parse_playback_info(state, value, value_len);
            return true;
        }
        /* Player Name and Volume are intentionally ignored. */
        return false;

    case AMS_ENTITY_QUEUE:
    default:
        return false;
    }
}
