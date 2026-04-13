/*
 * ancs_parser.h — Pure C parser for Apple Notification Center Service.
 *
 * ANCS is a BLE GATT service that iOS exposes to any connected BLE
 * peripheral. It pushes notification metadata (call, message, etc.) to
 * the peripheral so it can render an alert UI without needing any iOS
 * app code.
 *
 * For ScramScreen we only care about the IncomingCall and MissedCall
 * categories, which we map onto our existing `screen_call` payload.
 *
 * Wire format reference:
 *   https://developer.apple.com/library/archive/documentation/CoreBluetooth/Reference/AppleNotificationCenterServiceSpecification/Specification/Specification.html
 */
#ifndef ANCS_PARSER_H
#define ANCS_PARSER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ANCS service / characteristic UUIDs (128-bit, written here as
 * Apple's documented string form — convert to little-endian bytes
 * when registering with NimBLE). */
#define ANCS_SERVICE_UUID             "7905F431-B5CE-4E99-A40F-4B1E122D00D0"
#define ANCS_NOTIFICATION_SOURCE_UUID "9FBF120D-6301-42D9-8C58-25E699A21DBD"
#define ANCS_CONTROL_POINT_UUID       "69D1D8F3-45E1-49A8-9821-9BBDFDAAD9D9"
#define ANCS_DATA_SOURCE_UUID         "22EAC6E9-24D6-4BB5-BE44-B36ACE7C7BFB"

/* EventID values (byte 0 of a Notification Source notification). */
typedef enum {
    ANCS_EVENT_ADDED = 0,
    ANCS_EVENT_MODIFIED = 1,
    ANCS_EVENT_REMOVED = 2,
} ancs_event_id_t;

/* CategoryID values we care about. ANCS defines more (Email, Social, etc.)
 * but we only act on call categories. */
typedef enum {
    ANCS_CATEGORY_OTHER = 0,
    ANCS_CATEGORY_INCOMING_CALL = 1,
    ANCS_CATEGORY_MISSED_CALL = 2,
    ANCS_CATEGORY_VOICEMAIL = 3,
    /* Other categories defined by Apple but not used here:
     * 4 Social, 5 Schedule, 6 Email, 7 News, 8 HealthAndFitness,
     * 9 BusinessAndFinance, 10 Location, 11 Entertainment. */
} ancs_category_id_t;

/* AttributeID values used in Control Point requests / Data Source
 * responses. */
typedef enum {
    ANCS_ATTR_APP_IDENTIFIER = 0,
    ANCS_ATTR_TITLE = 1, /* For calls: caller name. */
    ANCS_ATTR_SUBTITLE = 2,
    ANCS_ATTR_MESSAGE = 3,
    ANCS_ATTR_MESSAGE_SIZE = 4,
    ANCS_ATTR_DATE = 5,
    ANCS_ATTR_POSITIVE_ACTION = 6,
    ANCS_ATTR_NEGATIVE_ACTION = 7,
} ancs_attribute_id_t;

/* CommandID values used in Control Point requests. */
typedef enum {
    ANCS_CMD_GET_NOTIFICATION_ATTRIBUTES = 0,
    ANCS_CMD_GET_APP_ATTRIBUTES = 1,
    ANCS_CMD_PERFORM_NOTIFICATION_ACTION = 2,
} ancs_command_id_t;

/* Decoded Notification Source notification (8 bytes on the wire). */
typedef struct {
    ancs_event_id_t event_id;
    uint8_t event_flags;
    ancs_category_id_t category_id;
    uint8_t category_count;
    uint32_t uid;
} ancs_notification_t;

/*
 * Parse the 8-byte Notification Source notification.
 * Returns false if `data` is too short or `out` is NULL.
 */
bool ancs_parse_notification_source(const uint8_t *data, size_t len, ancs_notification_t *out);

/*
 * Build a "Get Notification Attributes" request to write to the Control
 * Point characteristic. Requests the Title attribute (caller name) for
 * the given UID, capped at `max_len` bytes.
 *
 * The output buffer must be at least 8 bytes (1 cmd + 4 uid + 1 attr +
 * 2 max_len). Returns the number of bytes written, or 0 on failure.
 */
size_t ancs_build_get_title_request(uint32_t uid, uint16_t max_len, uint8_t *out_buf,
                                    size_t out_cap);

/*
 * Parse a Data Source response. The response wraps the requested
 * attributes after a small command header. We only extract the Title
 * attribute value into `out_title` (null-terminated, truncated if
 * needed).
 *
 * Returns true if a Title attribute was found and copied.
 */
bool ancs_parse_data_source_title(const uint8_t *data, size_t len, char *out_title, size_t out_cap);

#ifdef __cplusplus
}
#endif

#endif /* ANCS_PARSER_H */
