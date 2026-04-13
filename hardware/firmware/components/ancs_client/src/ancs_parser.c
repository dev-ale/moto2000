/*
 * ancs_parser.c — Pure C parser for Apple Notification Center Service.
 *
 * See ancs_parser.h for the wire format reference.
 */
#include "ancs_parser.h"

#include <string.h>

#define ANCS_NS_NOTIFICATION_LEN 8

bool ancs_parse_notification_source(const uint8_t *data, size_t len, ancs_notification_t *out)
{
    if (!data || !out || len < ANCS_NS_NOTIFICATION_LEN) {
        return false;
    }
    out->event_id = (ancs_event_id_t)data[0];
    out->event_flags = data[1];
    out->category_id = (ancs_category_id_t)data[2];
    out->category_count = data[3];
    out->uid = ((uint32_t)data[4]) | ((uint32_t)data[5] << 8) | ((uint32_t)data[6] << 16) |
               ((uint32_t)data[7] << 24);
    return true;
}

size_t ancs_build_get_title_request(uint32_t uid, uint16_t max_len, uint8_t *out_buf,
                                    size_t out_cap)
{
    if (!out_buf || out_cap < 8) {
        return 0;
    }
    out_buf[0] = (uint8_t)ANCS_CMD_GET_NOTIFICATION_ATTRIBUTES;
    out_buf[1] = (uint8_t)(uid & 0xFFu);
    out_buf[2] = (uint8_t)((uid >> 8) & 0xFFu);
    out_buf[3] = (uint8_t)((uid >> 16) & 0xFFu);
    out_buf[4] = (uint8_t)((uid >> 24) & 0xFFu);
    out_buf[5] = (uint8_t)ANCS_ATTR_TITLE;
    out_buf[6] = (uint8_t)(max_len & 0xFFu);
    out_buf[7] = (uint8_t)((max_len >> 8) & 0xFFu);
    return 8;
}

bool ancs_parse_data_source_title(const uint8_t *data, size_t len, char *out_title, size_t out_cap)
{
    if (!data || !out_title || out_cap == 0) {
        return false;
    }

    /* Data Source response format for GetNotificationAttributes:
     *   [0]    CommandID  (must be 0x00)
     *   [1..4] NotificationUID
     *   then for each requested attribute:
     *     [0]   AttributeID
     *     [1..2] AttributeLength (uint16 LE)
     *     [3..N] AttributeData (UTF-8, NOT null-terminated)
     */
    if (len < 5) {
        return false;
    }
    if (data[0] != (uint8_t)ANCS_CMD_GET_NOTIFICATION_ATTRIBUTES) {
        return false;
    }

    size_t pos = 5; /* Skip command + UID. */
    while (pos + 3 <= len) {
        uint8_t attr_id = data[pos];
        uint16_t attr_len = (uint16_t)((uint16_t)data[pos + 1] | ((uint16_t)data[pos + 2] << 8));
        pos += 3;
        if (pos + attr_len > len) {
            return false; /* Malformed. */
        }
        if (attr_id == (uint8_t)ANCS_ATTR_TITLE) {
            size_t copy_len = attr_len < (out_cap - 1) ? attr_len : (out_cap - 1);
            memcpy(out_title, data + pos, copy_len);
            out_title[copy_len] = '\0';
            return true;
        }
        pos += attr_len;
    }
    /* Title attribute not present in this response. */
    out_title[0] = '\0';
    return false;
}
