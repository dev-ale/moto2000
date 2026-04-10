/*
 * ble_protocol_call.c — incoming call body encoder/decoder.
 */
#include "ble_protocol.h"
#include "ble_protocol_internal.h"

#include <string.h>

#define CALLER_HANDLE_FIELD_LEN ((size_t)30)

static bool ble_call_state_is_known(uint8_t s)
{
    return s <= BLE_CALL_ENDED;
}

ble_result_t ble_decode_incoming_call(const uint8_t              *data,
                                      size_t                      length,
                                      uint8_t                    *out_flags,
                                      ble_incoming_call_data_t   *out_call)
{
    ble_header_t header;
    const ble_result_t hdr = ble_decode_header(data, length, &header);
    if (hdr != BLE_OK) {
        return hdr;
    }
    if (header.screen_id != BLE_SCREEN_INCOMING_CALL) {
        return BLE_ERR_UNKNOWN_SCREEN_ID;
    }
    if (header.body_length != BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE) {
        return BLE_ERR_BODY_LENGTH_MISMATCH;
    }
    const uint8_t *body     = header.body;
    const uint8_t  state    = body[0];
    const uint8_t  reserved = body[1];
    if (reserved != 0) {
        return BLE_ERR_NON_ZERO_BODY_RESERVED;
    }
    if (!ble_call_state_is_known(state)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    /* caller_handle: 30 bytes, must contain a null terminator */
    const uint8_t *handle = &body[2];
    bool terminator_found = false;
    for (size_t i = 0; i < CALLER_HANDLE_FIELD_LEN; ++i) {
        if (handle[i] == 0) {
            terminator_found = true;
            break;
        }
    }
    if (!terminator_found) {
        return BLE_ERR_UNTERMINATED_STRING;
    }

    out_call->call_state = (ble_call_state_t)state;
    memset(out_call->caller_handle, 0, sizeof(out_call->caller_handle));
    memcpy(out_call->caller_handle, handle, CALLER_HANDLE_FIELD_LEN);
    if (out_flags != NULL) {
        *out_flags = header.flags;
    }
    return BLE_OK;
}

ble_result_t ble_encode_incoming_call(const ble_incoming_call_data_t *call,
                                      uint8_t                         flags,
                                      uint8_t                        *out_buf,
                                      size_t                          out_cap,
                                      size_t                         *out_written)
{
    if (out_cap < BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE) {
        return BLE_ERR_BUFFER_TOO_SMALL;
    }
    if ((flags & BLE_FLAG_RESERVED_MASK) != 0) {
        return BLE_ERR_RESERVED_FLAGS_SET;
    }
    if (!ble_call_state_is_known((uint8_t)call->call_state)) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }
    /* caller_handle must fit with a null terminator. */
    size_t name_len = strnlen(call->caller_handle, CALLER_HANDLE_FIELD_LEN);
    if (name_len >= CALLER_HANDLE_FIELD_LEN) {
        return BLE_ERR_VALUE_OUT_OF_RANGE;
    }

    ble_write_header(out_buf, BLE_SCREEN_INCOMING_CALL, flags,
                     (uint16_t)BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE);
    uint8_t *body = out_buf + BLE_PROTOCOL_HEADER_SIZE;
    body[0] = (uint8_t)call->call_state;
    body[1] = 0; /* reserved */
    memset(&body[2], 0, CALLER_HANDLE_FIELD_LEN);
    memcpy(&body[2], call->caller_handle, name_len);
    if (out_written != NULL) {
        *out_written = BLE_PROTOCOL_HEADER_SIZE + BLE_PROTOCOL_INCOMING_CALL_BODY_SIZE;
    }
    return BLE_OK;
}
