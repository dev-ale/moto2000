/*
 * test_ams_parser.c — Unity tests for the Apple Media Service parser.
 *
 * Verifies that ams_apply_entity_update() correctly accumulates state
 * from per-attribute notifications. The wire format is documented in
 * components/ams_client/include/ams_parser.h.
 */
#include <string.h>

#include "unity.h"

#include "ams_parser.h"

void setUp(void) {}
void tearDown(void) {}

/* Helper: build a single Entity Update notification on the stack and
 * apply it to `state`. The format is [entity, attribute, flags, value...]. */
static bool apply_update(ams_state_t *state, uint8_t entity, uint8_t attr, const char *value)
{
    uint8_t buf[128];
    size_t vlen = value ? strlen(value) : 0;
    if (vlen > sizeof(buf) - 3) {
        vlen = sizeof(buf) - 3;
    }
    buf[0] = entity;
    buf[1] = attr;
    buf[2] = 0; /* flags */
    if (vlen > 0) {
        memcpy(buf + 3, value, vlen);
    }
    return ams_apply_entity_update(state, buf, 3 + vlen);
}

/* ------------------------------------------------------------------ */
/* init                                                                */
/* ------------------------------------------------------------------ */

static void test_init_sets_unknown_sentinels(void)
{
    ams_state_t state;
    ams_state_init(&state);

    TEST_ASSERT_EQUAL_STRING("", state.title);
    TEST_ASSERT_EQUAL_STRING("", state.artist);
    TEST_ASSERT_EQUAL_STRING("", state.album);
    TEST_ASSERT_EQUAL_UINT16(0xFFFFu, state.duration_seconds);
    TEST_ASSERT_EQUAL_UINT16(0xFFFFu, state.position_seconds);
    TEST_ASSERT_FALSE(state.is_playing);
}

static void test_init_null_state_does_not_crash(void)
{
    ams_state_init(NULL);
}

/* ------------------------------------------------------------------ */
/* track attributes                                                    */
/* ------------------------------------------------------------------ */

static void test_track_title_short_string(void)
{
    ams_state_t state;
    ams_state_init(&state);

    bool changed = apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_TITLE, "Bohemian Rhapsody");
    TEST_ASSERT_TRUE(changed);
    TEST_ASSERT_EQUAL_STRING("Bohemian Rhapsody", state.title);
}

static void test_track_artist_and_album(void)
{
    ams_state_t state;
    ams_state_init(&state);

    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_ARTIST, "Queen");
    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_ALBUM, "A Night at the Opera");

    TEST_ASSERT_EQUAL_STRING("Queen", state.artist);
    TEST_ASSERT_EQUAL_STRING("A Night at the Opera", state.album);
}

static void test_track_title_truncates_to_field_size(void)
{
    /* Title field is 32 bytes including the NUL, so 31 chars max. */
    ams_state_t state;
    ams_state_init(&state);

    const char *long_title = "0123456789012345678901234567890123456789"; /* 40 chars */
    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_TITLE, long_title);

    TEST_ASSERT_EQUAL_INT(31, (int)strlen(state.title));
    TEST_ASSERT_EQUAL_STRING_LEN(long_title, state.title, 31);
}

static void test_track_artist_truncates_to_field_size(void)
{
    /* Artist field is 24 bytes, 23 chars + NUL. */
    ams_state_t state;
    ams_state_init(&state);

    const char *long_artist = "012345678901234567890123456789"; /* 30 chars */
    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_ARTIST, long_artist);

    TEST_ASSERT_EQUAL_INT(23, (int)strlen(state.artist));
}

static void test_track_duration_parses_float_seconds(void)
{
    ams_state_t state;
    ams_state_init(&state);

    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_DURATION, "245.512");
    TEST_ASSERT_EQUAL_UINT16(245, state.duration_seconds);

    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_DURATION, "0");
    TEST_ASSERT_EQUAL_UINT16(0, state.duration_seconds);

    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_DURATION, "3600");
    TEST_ASSERT_EQUAL_UINT16(3600, state.duration_seconds);
}

static void test_track_duration_garbage_yields_unknown(void)
{
    ams_state_t state;
    ams_state_init(&state);
    state.duration_seconds = 100; /* sentinel different from 0xFFFF */

    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_DURATION, "not-a-number");
    TEST_ASSERT_EQUAL_UINT16(0xFFFFu, state.duration_seconds);
}

static void test_track_empty_string_clears_field(void)
{
    ams_state_t state;
    ams_state_init(&state);

    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_TITLE, "Initial");
    TEST_ASSERT_EQUAL_STRING("Initial", state.title);

    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_TITLE, "");
    TEST_ASSERT_EQUAL_STRING("", state.title);
}

/* ------------------------------------------------------------------ */
/* player attributes                                                   */
/* ------------------------------------------------------------------ */

static void test_player_playback_info_playing_with_position(void)
{
    ams_state_t state;
    ams_state_init(&state);

    /* state=1 (playing), rate=1.0, elapsed=42.5 */
    apply_update(&state, AMS_ENTITY_PLAYER, AMS_PLAYER_PLAYBACK_INFO, "1,1,42.5");

    TEST_ASSERT_TRUE(state.is_playing);
    TEST_ASSERT_EQUAL_UINT16(42, state.position_seconds);
}

static void test_player_playback_info_paused(void)
{
    ams_state_t state;
    ams_state_init(&state);

    apply_update(&state, AMS_ENTITY_PLAYER, AMS_PLAYER_PLAYBACK_INFO, "0,0,128.0");

    TEST_ASSERT_FALSE(state.is_playing);
    TEST_ASSERT_EQUAL_UINT16(128, state.position_seconds);
}

static void test_player_playback_info_missing_elapsed(void)
{
    ams_state_t state;
    ams_state_init(&state);
    state.position_seconds = 99;

    /* No elapsed field present. */
    apply_update(&state, AMS_ENTITY_PLAYER, AMS_PLAYER_PLAYBACK_INFO, "1,1.0");

    TEST_ASSERT_TRUE(state.is_playing);
    TEST_ASSERT_EQUAL_UINT16(99, state.position_seconds); /* unchanged */
}

static void test_player_name_attribute_is_ignored(void)
{
    ams_state_t state;
    ams_state_init(&state);

    bool changed = apply_update(&state, AMS_ENTITY_PLAYER, AMS_PLAYER_NAME, "Music");
    TEST_ASSERT_FALSE(changed);
    TEST_ASSERT_FALSE(state.is_playing);
}

/* ------------------------------------------------------------------ */
/* combined updates                                                    */
/* ------------------------------------------------------------------ */

static void test_full_track_sequence_accumulates_into_one_state(void)
{
    ams_state_t state;
    ams_state_init(&state);

    /* iOS pushes one notification per (entity, attribute) pair when it
     * updates a field. Verify they all combine correctly. */
    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_TITLE, "Don't Stop Me Now");
    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_ARTIST, "Queen");
    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_ALBUM, "Jazz");
    apply_update(&state, AMS_ENTITY_TRACK, AMS_TRACK_DURATION, "209");
    apply_update(&state, AMS_ENTITY_PLAYER, AMS_PLAYER_PLAYBACK_INFO, "1,1.0,12.0");

    TEST_ASSERT_EQUAL_STRING("Don't Stop Me Now", state.title);
    TEST_ASSERT_EQUAL_STRING("Queen", state.artist);
    TEST_ASSERT_EQUAL_STRING("Jazz", state.album);
    TEST_ASSERT_EQUAL_UINT16(209, state.duration_seconds);
    TEST_ASSERT_EQUAL_UINT16(12, state.position_seconds);
    TEST_ASSERT_TRUE(state.is_playing);
}

/* ------------------------------------------------------------------ */
/* malformed inputs                                                    */
/* ------------------------------------------------------------------ */

static void test_short_buffer_returns_false(void)
{
    ams_state_t state;
    ams_state_init(&state);
    uint8_t buf[2] = { 0, 0 };

    TEST_ASSERT_FALSE(ams_apply_entity_update(&state, buf, 2));
    TEST_ASSERT_FALSE(ams_apply_entity_update(&state, buf, 0));
    TEST_ASSERT_FALSE(ams_apply_entity_update(&state, NULL, 4));
    TEST_ASSERT_FALSE(ams_apply_entity_update(NULL, buf, 4));
}

static void test_unknown_entity_returns_false(void)
{
    ams_state_t state;
    ams_state_init(&state);

    bool changed = apply_update(&state, 99, 0, "anything");
    TEST_ASSERT_FALSE(changed);
}

static void test_unknown_track_attribute_returns_false(void)
{
    ams_state_t state;
    ams_state_init(&state);

    bool changed = apply_update(&state, AMS_ENTITY_TRACK, 99, "anything");
    TEST_ASSERT_FALSE(changed);
}

/* ------------------------------------------------------------------ */
/* main                                                                */
/* ------------------------------------------------------------------ */

int main(void)
{
    UNITY_BEGIN();

    RUN_TEST(test_init_sets_unknown_sentinels);
    RUN_TEST(test_init_null_state_does_not_crash);
    RUN_TEST(test_track_title_short_string);
    RUN_TEST(test_track_artist_and_album);
    RUN_TEST(test_track_title_truncates_to_field_size);
    RUN_TEST(test_track_artist_truncates_to_field_size);
    RUN_TEST(test_track_duration_parses_float_seconds);
    RUN_TEST(test_track_duration_garbage_yields_unknown);
    RUN_TEST(test_track_empty_string_clears_field);
    RUN_TEST(test_player_playback_info_playing_with_position);
    RUN_TEST(test_player_playback_info_paused);
    RUN_TEST(test_player_playback_info_missing_elapsed);
    RUN_TEST(test_player_name_attribute_is_ignored);
    RUN_TEST(test_full_track_sequence_accumulates_into_one_state);
    RUN_TEST(test_short_buffer_returns_false);
    RUN_TEST(test_unknown_entity_returns_false);
    RUN_TEST(test_unknown_track_attribute_returns_false);

    return UNITY_END();
}
