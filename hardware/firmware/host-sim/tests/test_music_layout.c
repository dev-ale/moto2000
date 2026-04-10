/*
 * test_music_layout.c — Unity host tests for the music layout helpers.
 */
#include "unity.h"

#include "host_sim/music_layout.h"

#include <string.h>

void setUp(void) {}
void tearDown(void) {}

/* -------------------------------------------------------------------- */
/* progress bar fill width                                              */
/* -------------------------------------------------------------------- */

static void test_progress_zero_when_position_zero(void)
{
    TEST_ASSERT_EQUAL_INT(0, host_sim_music_progress_fill_width(0, 100, 200));
}

static void test_progress_half(void)
{
    TEST_ASSERT_EQUAL_INT(100, host_sim_music_progress_fill_width(50, 100, 200));
}

static void test_progress_full_when_position_equals_duration(void)
{
    TEST_ASSERT_EQUAL_INT(200, host_sim_music_progress_fill_width(100, 100, 200));
}

static void test_progress_clamped_when_position_exceeds_duration(void)
{
    TEST_ASSERT_EQUAL_INT(200, host_sim_music_progress_fill_width(500, 100, 200));
}

static void test_progress_indeterminate_when_position_unknown(void)
{
    TEST_ASSERT_EQUAL_INT(-1,
                          host_sim_music_progress_fill_width(HOST_SIM_MUSIC_UNKNOWN_U16, 100, 200));
}

static void test_progress_indeterminate_when_duration_unknown(void)
{
    TEST_ASSERT_EQUAL_INT(-1,
                          host_sim_music_progress_fill_width(50, HOST_SIM_MUSIC_UNKNOWN_U16, 200));
}

static void test_progress_zero_when_duration_zero(void)
{
    TEST_ASSERT_EQUAL_INT(0, host_sim_music_progress_fill_width(50, 0, 200));
}

/* -------------------------------------------------------------------- */
/* truncate with ellipsis                                               */
/* -------------------------------------------------------------------- */

static void test_truncate_passthrough(void)
{
    char out[16];
    const size_t n = host_sim_music_truncate_with_ellipsis("ABC", out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("ABC", out);
    TEST_ASSERT_EQUAL_size_t(3, n);
}

static void test_truncate_appends_ellipsis(void)
{
    char out[8]; /* capacity 8 → max 7 chars + NUL */
    const size_t n = host_sim_music_truncate_with_ellipsis("ABCDEFGHIJ", out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("ABCDE..", out);
    TEST_ASSERT_EQUAL_size_t(7, n);
}

static void test_truncate_exact_fit(void)
{
    char out[8];
    const size_t n = host_sim_music_truncate_with_ellipsis("ABCDEFG", out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("ABCDEFG", out);
    TEST_ASSERT_EQUAL_size_t(7, n);
}

static void test_truncate_empty(void)
{
    char out[8];
    const size_t n = host_sim_music_truncate_with_ellipsis("", out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("", out);
    TEST_ASSERT_EQUAL_size_t(0, n);
}

static void test_truncate_null_input(void)
{
    char out[8];
    (void)host_sim_music_truncate_with_ellipsis(NULL, out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("", out);
}

/* -------------------------------------------------------------------- */
/* uppercase                                                            */
/* -------------------------------------------------------------------- */

static void test_uppercase_basic(void)
{
    char out[16];
    host_sim_music_uppercase_ascii("Hello World", out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("HELLO WORLD", out);
}

static void test_uppercase_clamps_to_buffer(void)
{
    char out[6];
    host_sim_music_uppercase_ascii("abcdefghij", out, sizeof(out));
    /* out_len=6 → 5 chars + NUL */
    TEST_ASSERT_EQUAL_STRING("ABCDE", out);
}

static void test_uppercase_leaves_nonletters_alone(void)
{
    char out[16];
    host_sim_music_uppercase_ascii("A1b 2.c", out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("A1B 2.C", out);
}

static void test_uppercase_empty(void)
{
    char out[8];
    host_sim_music_uppercase_ascii("", out, sizeof(out));
    TEST_ASSERT_EQUAL_STRING("", out);
}

/* -------------------------------------------------------------------- */
/* format time                                                          */
/* -------------------------------------------------------------------- */

static void test_format_time_basic(void)
{
    char buf[12];
    host_sim_music_format_time(84, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1:24", buf);
}

static void test_format_time_two_digit_minutes(void)
{
    char buf[12];
    host_sim_music_format_time(754, buf, sizeof(buf)); /* 12:34 */
    TEST_ASSERT_EQUAL_STRING("12:34", buf);
}

static void test_format_time_zero(void)
{
    char buf[12];
    host_sim_music_format_time(0, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("0:00", buf);
}

static void test_format_time_unknown_sentinel(void)
{
    char buf[12];
    host_sim_music_format_time(HOST_SIM_MUSIC_UNKNOWN_U16, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("--:--", buf);
}

static void test_format_time_leading_zero_in_seconds(void)
{
    char buf[12];
    host_sim_music_format_time(65, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1:05", buf);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_progress_zero_when_position_zero);
    RUN_TEST(test_progress_half);
    RUN_TEST(test_progress_full_when_position_equals_duration);
    RUN_TEST(test_progress_clamped_when_position_exceeds_duration);
    RUN_TEST(test_progress_indeterminate_when_position_unknown);
    RUN_TEST(test_progress_indeterminate_when_duration_unknown);
    RUN_TEST(test_progress_zero_when_duration_zero);

    RUN_TEST(test_truncate_passthrough);
    RUN_TEST(test_truncate_appends_ellipsis);
    RUN_TEST(test_truncate_exact_fit);
    RUN_TEST(test_truncate_empty);
    RUN_TEST(test_truncate_null_input);

    RUN_TEST(test_uppercase_basic);
    RUN_TEST(test_uppercase_clamps_to_buffer);
    RUN_TEST(test_uppercase_leaves_nonletters_alone);
    RUN_TEST(test_uppercase_empty);

    RUN_TEST(test_format_time_basic);
    RUN_TEST(test_format_time_two_digit_minutes);
    RUN_TEST(test_format_time_zero);
    RUN_TEST(test_format_time_unknown_sentinel);
    RUN_TEST(test_format_time_leading_zero_in_seconds);
    return UNITY_END();
}
