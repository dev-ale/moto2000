/*
 * screen_fsm — ESP32 side of Slice 5 (screen switching + alert overlay).
 *
 * Pure C with no ESP-IDF dependencies so the same translation unit compiles
 * under the host-test harness at hardware/firmware/test/host/.
 *
 * The state machine owns three pieces of state:
 *
 *   - state              the macro state (active / alert overlay / sleep)
 *   - active_screen_id   the persistent "return to" screen the user picked
 *                        (or that the iOS app last requested)
 *   - current_display_id what the panel is rendering right this instant
 *
 * The active id and current id can diverge during an alert overlay or while
 * sleeping. They are only re-synced when the FSM emits a render action.
 *
 * Behaviour summary (full table in test_screen_fsm.c):
 *
 *   ACTIVE        + SET_ACTIVE          -> render new screen, ACTIVE
 *   ACTIVE        + ALERT_INCOMING      -> render alert,      ALERT_OVERLAY
 *   ACTIVE        + CLEAR_ALERT         -> no-op,             ACTIVE
 *   ACTIVE        + SLEEP               -> dim,               SLEEP
 *   ACTIVE        + WAKE                -> no-op,             ACTIVE
 *   ACTIVE        + DATA_ARRIVED(=act)  -> re-render,         ACTIVE
 *   ACTIVE        + DATA_ARRIVED(!=act) -> ignore,            ACTIVE
 *
 *   ALERT_OVERLAY + SET_ACTIVE          -> remember new id, stay overlay
 *   ALERT_OVERLAY + ALERT_INCOMING(>p)  -> render new alert,  ALERT_OVERLAY
 *   ALERT_OVERLAY + ALERT_INCOMING(<=p) -> ignore,            ALERT_OVERLAY
 *   ALERT_OVERLAY + CLEAR_ALERT         -> render active,     ACTIVE
 *   ALERT_OVERLAY + SLEEP               -> dim,               SLEEP
 *   ALERT_OVERLAY + DATA_ARRIVED        -> ignore,            ALERT_OVERLAY
 *
 *   SLEEP         + WAKE                -> render active,     ACTIVE
 *   SLEEP         + SET_ACTIVE          -> remember id, stay  SLEEP
 *   SLEEP         + everything else     -> ignore,            SLEEP
 */
#ifndef SCRAMSCREEN_SCREEN_FSM_H
#define SCRAMSCREEN_SCREEN_FSM_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    SCREEN_FSM_ACTIVE = 0,
    SCREEN_FSM_ALERT_OVERLAY = 1,
    SCREEN_FSM_SLEEP = 2,
} screen_fsm_state_t;

typedef enum {
    SCREEN_FSM_EVT_CONTROL_SET_ACTIVE = 0,
    SCREEN_FSM_EVT_CONTROL_CLEAR_ALERT = 1,
    SCREEN_FSM_EVT_CONTROL_SLEEP = 2,
    SCREEN_FSM_EVT_CONTROL_WAKE = 3,
    SCREEN_FSM_EVT_ALERT_INCOMING = 4,
    SCREEN_FSM_EVT_DATA_ARRIVED = 5,
} screen_fsm_event_t;

typedef struct {
    screen_fsm_state_t state;
    uint8_t active_screen_id;
    uint8_t current_display_id;
    uint8_t alert_priority;
} screen_fsm_t;

typedef enum {
    SCREEN_FSM_ACTION_NONE = 0,
    SCREEN_FSM_ACTION_RENDER_SCREEN = 1,
    SCREEN_FSM_ACTION_DIM_DISPLAY = 2,
    SCREEN_FSM_ACTION_WAKE_DISPLAY = 3,
} screen_fsm_action_t;

typedef struct {
    screen_fsm_action_t kind;
    uint8_t screen_id;
} screen_fsm_outcome_t;

void screen_fsm_init(screen_fsm_t *fsm, uint8_t initial_active_screen_id);

/*
 * Drive the FSM with an event.
 *
 * Data interpretation:
 *   - SET_ACTIVE          : data = new active screen id
 *   - ALERT_INCOMING      : data = alert screen id; alert priority is stored
 *                           in the FSM directly via screen_fsm_set_alert
 *                           helper because we need both fields and only one
 *                           "data" byte. The convenience entry point
 *                           ``screen_fsm_handle_alert`` packs both into one
 *                           call.
 *   - DATA_ARRIVED        : data = screen id of the payload that arrived
 *   - CLEAR_ALERT/SLEEP/WAKE: data is ignored
 */
screen_fsm_outcome_t screen_fsm_handle(screen_fsm_t *fsm, screen_fsm_event_t event, uint8_t data);

/*
 * Convenience wrapper for an incoming alert. Equivalent to:
 *   set fsm internal "next alert priority" then handle ALERT_INCOMING.
 */
screen_fsm_outcome_t screen_fsm_handle_alert(screen_fsm_t *fsm, uint8_t alert_screen_id,
                                             uint8_t priority);

#ifdef __cplusplus
}
#endif

#endif /* SCRAMSCREEN_SCREEN_FSM_H */
