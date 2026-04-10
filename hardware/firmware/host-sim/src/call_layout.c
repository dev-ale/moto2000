/*
 * call_layout.c — pure helpers for the incoming call overlay.
 */
#include "call_layout.h"

#include <ctype.h>
#include <string.h>

const char *call_state_label(ble_call_state_t state)
{
    switch (state) {
    case BLE_CALL_INCOMING:
        return "INCOMING CALL";
    case BLE_CALL_CONNECTED:
        return "CONNECTED";
    case BLE_CALL_ENDED:
        return "ENDED";
    default:
        return "UNKNOWN";
    }
}

char call_avatar_initial(const char *caller_handle)
{
    if (caller_handle == NULL || caller_handle[0] == '\0') {
        return '?';
    }
    char c = caller_handle[0];
    if (c >= 'a' && c <= 'z') {
        return (char)(c - 'a' + 'A');
    }
    return c;
}
