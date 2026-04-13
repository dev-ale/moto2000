/*
 * ams_parser.h — Pure C parser for Apple Media Service notifications.
 *
 * Apple Media Service (AMS) is a BLE GATT service that iOS exposes to any
 * connected BLE peripheral. It pushes "now playing" metadata (track title,
 * artist, album, duration, playback state) regardless of which iOS app is
 * actually playing the audio (Spotify, Apple Music, Podcasts, etc.).
 *
 * This file contains only the parsing/state-management logic. The NimBLE
 * GATT client lives in src/ams_client.c (ESP-IDF only). Splitting them
 * lets us host-test the parser deterministically.
 *
 * Wire format reference:
 *   https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleMediaService_Reference/Specification/Specification.html
 */
#ifndef AMS_PARSER_H
#define AMS_PARSER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* AMS service / characteristic UUIDs (128-bit, written here as
 * Apple's documented string form — convert to little-endian bytes
 * when registering with NimBLE). */
#define AMS_SERVICE_UUID          "89D3502B-0F36-433A-8EF4-C502AD55F8DC"
#define AMS_REMOTE_COMMAND_UUID   "9B3C81D8-57B1-4A8A-B8DF-0E56F7CA51C2"
#define AMS_ENTITY_UPDATE_UUID    "2F7CABCE-808D-411F-9A0C-BB92BA96C102"
#define AMS_ENTITY_ATTRIBUTE_UUID "C6B2F38C-23AB-46D8-A6AB-A3A870BBD5D7"

/* Entity IDs as defined by Apple. */
typedef enum {
    AMS_ENTITY_PLAYER = 0,
    AMS_ENTITY_QUEUE = 1,
    AMS_ENTITY_TRACK = 2,
} ams_entity_id_t;

/* Player attribute IDs. */
typedef enum {
    AMS_PLAYER_NAME = 0,
    AMS_PLAYER_PLAYBACK_INFO = 1,
    AMS_PLAYER_VOLUME = 2,
} ams_player_attr_t;

/* Track attribute IDs. */
typedef enum {
    AMS_TRACK_ARTIST = 0,
    AMS_TRACK_ALBUM = 1,
    AMS_TRACK_TITLE = 2,
    AMS_TRACK_DURATION = 3,
} ams_track_attr_t;

/* Field sizes match ble_music_data_t in ble_protocol.h. */
#define AMS_TITLE_MAX_LEN  32
#define AMS_ARTIST_MAX_LEN 24
#define AMS_ALBUM_MAX_LEN  24

/*
 * Accumulated state from all AMS entity updates received so far.
 *
 * AMS sends one notification per (entity, attribute) tuple, so the
 * caller maintains a running state and patches in each update as it
 * arrives. After every successful parse, the state holds the latest
 * known values for every field.
 */
typedef struct {
    char title[AMS_TITLE_MAX_LEN];   /* null-terminated */
    char artist[AMS_ARTIST_MAX_LEN]; /* null-terminated */
    char album[AMS_ALBUM_MAX_LEN];   /* null-terminated */
    uint16_t duration_seconds;       /* 0xFFFF = unknown */
    uint16_t position_seconds;       /* 0xFFFF = unknown */
    bool is_playing;
} ams_state_t;

/* Reset all fields to "unknown" / empty. */
void ams_state_init(ams_state_t *state);

/*
 * Apply a single Entity Update notification to `state`.
 *
 * The notification format is:
 *   [0]    EntityID
 *   [1]    AttributeID
 *   [2]    EntityUpdateFlags (bit 0 = truncated)
 *   [3..N] AttributeValue (UTF-8 text, NOT null-terminated)
 *
 * Returns true if the state was modified, false if the notification
 * was ignored (unknown entity/attribute or malformed buffer).
 */
bool ams_apply_entity_update(ams_state_t *state, const uint8_t *data, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* AMS_PARSER_H */
