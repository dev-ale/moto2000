/*
 * call_layout.h — pure format helpers for the incoming call overlay.
 *
 * Layout choices:
 *   - State text: "INCOMING CALL" / "CONNECTED" / "ENDED"
 *   - Caller handle shown as-is (the iOS side truncates to 29 UTF-8 bytes).
 *   - Initial avatar circle placeholder rendered by the screen renderer.
 */
#ifndef HOST_SIM_CALL_LAYOUT_H
#define HOST_SIM_CALL_LAYOUT_H

#include <stddef.h>
#include <stdint.h>

#include "ble_protocol.h"

/*
 * Returns a human-readable state label for display.
 * Returns "UNKNOWN" for unrecognised values (defensive).
 */
const char *call_state_label(ble_call_state_t state);

/*
 * Returns an avatar placeholder character (first non-empty character
 * of the caller handle, uppercased ASCII if possible, or '?' if empty).
 */
char call_avatar_initial(const char *caller_handle);

#endif /* HOST_SIM_CALL_LAYOUT_H */
