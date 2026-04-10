/*
 * ble_protocol.h — ScramScreen BLE wire format codec.
 *
 * Pure C, no ESP-IDF dependencies. Mirrors the Swift BLEProtocol package.
 * Both are validated against the golden fixtures in protocol/fixtures/.
 *
 * Wire format is defined in docs/ble-protocol.md.
 */
#ifndef BLE_PROTOCOL_H
#define BLE_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BLE_PROTOCOL_VERSION       ((uint8_t)0x01)
#define BLE_PROTOCOL_HEADER_SIZE   ((size_t)8)
#define BLE_PROTOCOL_NAV_BODY_SIZE ((size_t)56)
#define BLE_PROTOCOL_CLOCK_BODY_SIZE ((size_t)12)
#define BLE_PROTOCOL_SPEED_HEADING_BODY_SIZE ((size_t)8)
#define BLE_PROTOCOL_COMPASS_BODY_SIZE ((size_t)8)
#define BLE_PROTOCOL_TRIP_STATS_BODY_SIZE ((size_t)16)
#define BLE_PROTOCOL_WEATHER_BODY_SIZE ((size_t)28)

/* Flag bits carried in the compass body flags byte. */
#define BLE_COMPASS_FLAG_USE_TRUE_HEADING (1U << 0)
#define BLE_COMPASS_FLAG_RESERVED_MASK    0xFEU

/* Sentinel value for true heading when the iOS heading fix is unavailable. */
#define BLE_COMPASS_TRUE_HEADING_UNKNOWN ((uint16_t)0xFFFFU)

/* Flag bits carried in the header flags byte. */
#define BLE_FLAG_ALERT      (1U << 0)
#define BLE_FLAG_NIGHT_MODE (1U << 1)
#define BLE_FLAG_STALE      (1U << 2)
#define BLE_FLAG_RESERVED_MASK 0xF8U

typedef enum {
    BLE_SCREEN_NAVIGATION    = 0x01,
    BLE_SCREEN_SPEED_HEADING = 0x02,
    BLE_SCREEN_COMPASS       = 0x03,
    BLE_SCREEN_WEATHER       = 0x04,
    BLE_SCREEN_TRIP_STATS    = 0x05,
    BLE_SCREEN_MUSIC         = 0x06,
    BLE_SCREEN_LEAN_ANGLE    = 0x07,
    BLE_SCREEN_BLITZER       = 0x08,
    BLE_SCREEN_INCOMING_CALL = 0x09,
    BLE_SCREEN_FUEL_ESTIMATE = 0x0A,
    BLE_SCREEN_ALTITUDE      = 0x0B,
    BLE_SCREEN_APPOINTMENT   = 0x0C,
    BLE_SCREEN_CLOCK         = 0x0D,
} ble_screen_id_t;

typedef enum {
    BLE_MANEUVER_NONE             = 0x00,
    BLE_MANEUVER_STRAIGHT         = 0x01,
    BLE_MANEUVER_SLIGHT_LEFT      = 0x02,
    BLE_MANEUVER_LEFT             = 0x03,
    BLE_MANEUVER_SHARP_LEFT       = 0x04,
    BLE_MANEUVER_U_TURN_LEFT      = 0x05,
    BLE_MANEUVER_SLIGHT_RIGHT     = 0x06,
    BLE_MANEUVER_RIGHT            = 0x07,
    BLE_MANEUVER_SHARP_RIGHT      = 0x08,
    BLE_MANEUVER_U_TURN_RIGHT     = 0x09,
    BLE_MANEUVER_ROUNDABOUT_ENTER = 0x0A,
    BLE_MANEUVER_ROUNDABOUT_EXIT  = 0x0B,
    BLE_MANEUVER_MERGE            = 0x0C,
    BLE_MANEUVER_FORK_LEFT        = 0x0D,
    BLE_MANEUVER_FORK_RIGHT       = 0x0E,
    BLE_MANEUVER_ARRIVE           = 0x0F,
} ble_maneuver_t;

typedef enum {
    BLE_OK = 0,
    BLE_ERR_TRUNCATED_HEADER,
    BLE_ERR_UNSUPPORTED_VERSION,
    BLE_ERR_INVALID_RESERVED,
    BLE_ERR_UNKNOWN_SCREEN_ID,
    BLE_ERR_TRUNCATED_BODY,
    BLE_ERR_BODY_LENGTH_MISMATCH,
    BLE_ERR_RESERVED_FLAGS_SET,
    BLE_ERR_UNTERMINATED_STRING,
    BLE_ERR_VALUE_OUT_OF_RANGE,
    BLE_ERR_NON_ZERO_BODY_RESERVED,
    BLE_ERR_BUFFER_TOO_SMALL,
    BLE_ERR_UNKNOWN_COMMAND,
    BLE_ERR_INVALID_COMMAND_VALUE,
} ble_result_t;

const char *ble_result_name(ble_result_t result);

typedef struct {
    int64_t unix_time;
    int16_t tz_offset_minutes;
    bool    is_24h;
} ble_clock_data_t;

typedef struct {
    uint16_t speed_kmh_x10;
    uint16_t heading_deg_x10;
    int16_t  altitude_m;
    int16_t  temperature_celsius_x10;
} ble_speed_heading_data_t;

typedef enum {
    BLE_WEATHER_CLEAR         = 0x00,
    BLE_WEATHER_CLOUDY        = 0x01,
    BLE_WEATHER_RAIN          = 0x02,
    BLE_WEATHER_SNOW          = 0x03,
    BLE_WEATHER_FOG           = 0x04,
    BLE_WEATHER_THUNDERSTORM  = 0x05,
} ble_weather_condition_t;

typedef struct {
    ble_weather_condition_t condition;
    int16_t                 temperature_celsius_x10;
    int16_t                 high_celsius_x10;
    int16_t                 low_celsius_x10;
    char                    location_name[20]; /* null-terminated UTF-8 */
} ble_weather_data_t;

typedef struct {
    uint16_t magnetic_heading_deg_x10;
    uint16_t true_heading_deg_x10;       /* 0xFFFF = unknown */
    uint16_t heading_accuracy_deg_x10;
    uint8_t  compass_flags;              /* bit 0 = BLE_COMPASS_FLAG_USE_TRUE_HEADING */
} ble_compass_data_t;

typedef struct {
    int32_t        latitude_e7;
    int32_t        longitude_e7;
    uint16_t       speed_kmh_x10;
    uint16_t       heading_deg_x10;
    uint16_t       distance_to_maneuver_m;
    ble_maneuver_t maneuver;
    char           street_name[32]; /* null-terminated UTF-8 */
    uint16_t       eta_minutes;
    uint16_t       remaining_km_x10;
} ble_nav_data_t;

typedef struct {
    uint32_t ride_time_seconds;
    uint32_t distance_meters;
    uint16_t average_speed_kmh_x10;
    uint16_t max_speed_kmh_x10;
    uint16_t ascent_meters;
    uint16_t descent_meters;
} ble_trip_stats_data_t;

typedef struct {
    ble_screen_id_t screen_id;
    uint8_t         flags;
    uint16_t        body_length;
    const uint8_t  *body;
} ble_header_t;

/*
 * Low-level header decoding. Validates version, reserved, and flags
 * reserved bits. Sets out_header->body to point inside `data`.
 */
ble_result_t ble_decode_header(const uint8_t *data,
                               size_t         length,
                               ble_header_t  *out_header);

/*
 * High-level screen decoders. They validate the header, check body length
 * against the expected size for the screen, and then decode the body.
 */
ble_result_t ble_decode_clock(const uint8_t    *data,
                              size_t            length,
                              uint8_t          *out_flags,
                              ble_clock_data_t *out_clock);

ble_result_t ble_decode_nav(const uint8_t  *data,
                            size_t          length,
                            uint8_t        *out_flags,
                            ble_nav_data_t *out_nav);

ble_result_t ble_decode_speed_heading(const uint8_t             *data,
                                      size_t                     length,
                                      uint8_t                   *out_flags,
                                      ble_speed_heading_data_t  *out);

/*
 * Encoders. `out_buf` must point to a buffer of at least
 * BLE_PROTOCOL_HEADER_SIZE + body_size bytes. On success, *out_written is
 * set to the number of bytes written.
 */
ble_result_t ble_encode_clock(const ble_clock_data_t *clock,
                              uint8_t                 flags,
                              uint8_t                *out_buf,
                              size_t                  out_cap,
                              size_t                 *out_written);

ble_result_t ble_encode_nav(const ble_nav_data_t *nav,
                            uint8_t               flags,
                            uint8_t              *out_buf,
                            size_t                out_cap,
                            size_t               *out_written);

ble_result_t ble_encode_speed_heading(const ble_speed_heading_data_t *in,
                                      uint8_t                         flags,
                                      uint8_t                        *out_buf,
                                      size_t                          out_cap,
                                      size_t                         *out_written);

ble_result_t ble_decode_compass(const uint8_t      *data,
                                size_t              length,
                                uint8_t            *out_flags,
                                ble_compass_data_t *out_compass);

ble_result_t ble_encode_compass(const ble_compass_data_t *in,
                                uint8_t                   flags,
                                uint8_t                  *out_buf,
                                size_t                    out_cap,
                                size_t                   *out_written);

/* ----- Control characteristic (Slice 5) -------------------------------- */

#define BLE_CONTROL_PAYLOAD_SIZE ((size_t)4)

typedef enum {
    BLE_CONTROL_CMD_SET_ACTIVE_SCREEN = 0x01,
    BLE_CONTROL_CMD_SET_BRIGHTNESS    = 0x02,
    BLE_CONTROL_CMD_SLEEP             = 0x03,
    BLE_CONTROL_CMD_WAKE              = 0x04,
    BLE_CONTROL_CMD_CLEAR_ALERT       = 0x05,
} ble_control_command_t;

typedef struct {
    ble_control_command_t command;
    /* Active screen ID for SET_ACTIVE_SCREEN, otherwise 0. */
    uint8_t screen_id;
    /* Brightness percentage 0..100 for SET_BRIGHTNESS, otherwise 0. */
    uint8_t brightness;
} ble_control_payload_t;

/*
 * Encode a control command into out_buf. out_buf must be at least
 * BLE_CONTROL_PAYLOAD_SIZE bytes. On success, *out_written is set to
 * BLE_CONTROL_PAYLOAD_SIZE.
 */
ble_result_t ble_encode_control(const ble_control_payload_t *in,
                                uint8_t                     *out_buf,
                                size_t                       out_cap,
                                size_t                      *out_written);

/*
 * Decode a 4-byte control command. Returns BLE_OK and fills out_payload on
 * success.
 */
ble_result_t ble_decode_control(const uint8_t         *data,
                                size_t                 length,
                                ble_control_payload_t *out_payload);

ble_result_t ble_decode_trip_stats(const uint8_t            *data,
                                   size_t                    length,
                                   uint8_t                  *out_flags,
                                   ble_trip_stats_data_t    *out);

ble_result_t ble_encode_trip_stats(const ble_trip_stats_data_t *in,
                                   uint8_t                      flags,
                                   uint8_t                     *out_buf,
                                   size_t                       out_cap,
                                   size_t                      *out_written);

ble_result_t ble_decode_weather(const uint8_t      *data,
                                size_t              length,
                                uint8_t            *out_flags,
                                ble_weather_data_t *out);

ble_result_t ble_encode_weather(const ble_weather_data_t *in,
                                uint8_t                   flags,
                                uint8_t                  *out_buf,
                                size_t                    out_cap,
                                size_t                   *out_written);

#ifdef __cplusplus
}
#endif

#endif /* BLE_PROTOCOL_H */
