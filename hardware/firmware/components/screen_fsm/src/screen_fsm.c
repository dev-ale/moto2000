/*
 * screen_fsm.c — implementation. See include/screen_fsm.h for the API
 * contract and behaviour table.
 */
#include "screen_fsm.h"

#include <string.h>

void screen_fsm_init(screen_fsm_t *fsm, uint8_t initial_active_screen_id)
{
    if (fsm == NULL) {
        return;
    }
    fsm->state              = SCREEN_FSM_ACTIVE;
    fsm->active_screen_id   = initial_active_screen_id;
    fsm->current_display_id = initial_active_screen_id;
    fsm->alert_priority     = 0u;
}

static screen_fsm_outcome_t make_none(void)
{
    screen_fsm_outcome_t out;
    out.kind      = SCREEN_FSM_ACTION_NONE;
    out.screen_id = 0u;
    return out;
}

static screen_fsm_outcome_t make_render(uint8_t id)
{
    screen_fsm_outcome_t out;
    out.kind      = SCREEN_FSM_ACTION_RENDER_SCREEN;
    out.screen_id = id;
    return out;
}

static screen_fsm_outcome_t make_dim(void)
{
    screen_fsm_outcome_t out;
    out.kind      = SCREEN_FSM_ACTION_DIM_DISPLAY;
    out.screen_id = 0u;
    return out;
}

static screen_fsm_outcome_t make_wake(uint8_t id)
{
    screen_fsm_outcome_t out;
    out.kind      = SCREEN_FSM_ACTION_WAKE_DISPLAY;
    out.screen_id = id;
    return out;
}

screen_fsm_outcome_t screen_fsm_handle(screen_fsm_t      *fsm,
                                       screen_fsm_event_t event,
                                       uint8_t            data)
{
    if (fsm == NULL) {
        return make_none();
    }

    switch (fsm->state) {
    case SCREEN_FSM_ACTIVE:
        switch (event) {
        case SCREEN_FSM_EVT_CONTROL_SET_ACTIVE:
            fsm->active_screen_id   = data;
            fsm->current_display_id = data;
            return make_render(data);
        case SCREEN_FSM_EVT_ALERT_INCOMING:
            fsm->state              = SCREEN_FSM_ALERT_OVERLAY;
            fsm->current_display_id = data;
            /* alert_priority is set by the convenience wrapper. */
            return make_render(data);
        case SCREEN_FSM_EVT_CONTROL_CLEAR_ALERT:
            return make_none();
        case SCREEN_FSM_EVT_CONTROL_SLEEP:
            fsm->state = SCREEN_FSM_SLEEP;
            return make_dim();
        case SCREEN_FSM_EVT_CONTROL_WAKE:
            return make_none();
        case SCREEN_FSM_EVT_DATA_ARRIVED:
            if (data == fsm->active_screen_id) {
                fsm->current_display_id = data;
                return make_render(data);
            }
            return make_none();
        default:
            return make_none();
        }

    case SCREEN_FSM_ALERT_OVERLAY:
        switch (event) {
        case SCREEN_FSM_EVT_CONTROL_SET_ACTIVE:
            /* Remember the new return-to screen but stay in the overlay. */
            fsm->active_screen_id = data;
            return make_none();
        case SCREEN_FSM_EVT_ALERT_INCOMING:
            /* Caller used the convenience wrapper which already replaced
             * alert_priority. Render only if the priority is strictly
             * higher; the wrapper restores the prior priority on a tie. */
            fsm->current_display_id = data;
            return make_render(data);
        case SCREEN_FSM_EVT_CONTROL_CLEAR_ALERT:
            fsm->state              = SCREEN_FSM_ACTIVE;
            fsm->alert_priority     = 0u;
            fsm->current_display_id = fsm->active_screen_id;
            return make_render(fsm->active_screen_id);
        case SCREEN_FSM_EVT_CONTROL_SLEEP:
            fsm->state          = SCREEN_FSM_SLEEP;
            fsm->alert_priority = 0u;
            return make_dim();
        case SCREEN_FSM_EVT_CONTROL_WAKE:
            return make_none();
        case SCREEN_FSM_EVT_DATA_ARRIVED:
            return make_none();
        default:
            return make_none();
        }

    case SCREEN_FSM_SLEEP:
        switch (event) {
        case SCREEN_FSM_EVT_CONTROL_WAKE:
            fsm->state              = SCREEN_FSM_ACTIVE;
            fsm->current_display_id = fsm->active_screen_id;
            return make_wake(fsm->active_screen_id);
        case SCREEN_FSM_EVT_CONTROL_SET_ACTIVE:
            /* Remember the new screen but stay asleep until WAKE. */
            fsm->active_screen_id = data;
            return make_none();
        case SCREEN_FSM_EVT_CONTROL_SLEEP:
        case SCREEN_FSM_EVT_CONTROL_CLEAR_ALERT:
        case SCREEN_FSM_EVT_ALERT_INCOMING:
        case SCREEN_FSM_EVT_DATA_ARRIVED:
            return make_none();
        default:
            return make_none();
        }

    default:
        return make_none();
    }
}

screen_fsm_outcome_t screen_fsm_handle_alert(screen_fsm_t *fsm,
                                             uint8_t       alert_screen_id,
                                             uint8_t       priority)
{
    if (fsm == NULL) {
        return make_none();
    }
    if (fsm->state == SCREEN_FSM_SLEEP) {
        return make_none();
    }
    if (fsm->state == SCREEN_FSM_ALERT_OVERLAY) {
        if (priority <= fsm->alert_priority) {
            return make_none();
        }
        fsm->alert_priority = priority;
        return screen_fsm_handle(fsm, SCREEN_FSM_EVT_ALERT_INCOMING, alert_screen_id);
    }
    /* SCREEN_FSM_ACTIVE */
    fsm->alert_priority = priority;
    return screen_fsm_handle(fsm, SCREEN_FSM_EVT_ALERT_INCOMING, alert_screen_id);
}
