/*
 * test_ancs_parser.c — Unity tests for the Apple Notification Center Service parser.
 */
#include <string.h>

#include "unity.h"

#include "ancs_parser.h"

void setUp(void) {}
void tearDown(void) {}

/* ------------------------------------------------------------------ */
/* notification source parsing                                         */
/* ------------------------------------------------------------------ */

static void test_parse_incoming_call_notification(void)
{
    /* Wire format: [event, flags, category, count, uid_le32] */
    const uint8_t buf[8] = {
        ANCS_EVENT_ADDED,
        0, /* event flags */
        ANCS_CATEGORY_INCOMING_CALL,
        1, /* category count */
        0xEF,
        0xBE,
        0xAD,
        0xDE, /* UID = 0xDEADBEEF */
    };

    ancs_notification_t out;
    bool ok = ancs_parse_notification_source(buf, sizeof(buf), &out);

    TEST_ASSERT_TRUE(ok);
    TEST_ASSERT_EQUAL_INT(ANCS_EVENT_ADDED, (int)out.event_id);
    TEST_ASSERT_EQUAL_UINT8(0, out.event_flags);
    TEST_ASSERT_EQUAL_INT(ANCS_CATEGORY_INCOMING_CALL, (int)out.category_id);
    TEST_ASSERT_EQUAL_UINT8(1, out.category_count);
    TEST_ASSERT_EQUAL_UINT32(0xDEADBEEFu, out.uid);
}

static void test_parse_call_removed_notification(void)
{
    const uint8_t buf[8] = {
        ANCS_EVENT_REMOVED, 0, ANCS_CATEGORY_INCOMING_CALL, 0, 0x01, 0x00, 0x00, 0x00,
    };
    ancs_notification_t out;
    TEST_ASSERT_TRUE(ancs_parse_notification_source(buf, sizeof(buf), &out));
    TEST_ASSERT_EQUAL_INT(ANCS_EVENT_REMOVED, (int)out.event_id);
    TEST_ASSERT_EQUAL_UINT32(1u, out.uid);
}

static void test_parse_missed_call_notification(void)
{
    const uint8_t buf[8] = {
        ANCS_EVENT_ADDED, 0, ANCS_CATEGORY_MISSED_CALL, 1, 0x10, 0x00, 0x00, 0x00,
    };
    ancs_notification_t out;
    TEST_ASSERT_TRUE(ancs_parse_notification_source(buf, sizeof(buf), &out));
    TEST_ASSERT_EQUAL_INT(ANCS_CATEGORY_MISSED_CALL, (int)out.category_id);
    TEST_ASSERT_EQUAL_UINT32(0x10u, out.uid);
}

static void test_parse_other_category_still_decodes(void)
{
    /* Categories we don't act on still decode cleanly. The caller is
     * responsible for filtering. */
    const uint8_t buf[8] = {
        ANCS_EVENT_ADDED, 0, ANCS_CATEGORY_OTHER, 1, 0xAA, 0xBB, 0xCC, 0xDD,
    };
    ancs_notification_t out;
    TEST_ASSERT_TRUE(ancs_parse_notification_source(buf, sizeof(buf), &out));
    TEST_ASSERT_EQUAL_INT(ANCS_CATEGORY_OTHER, (int)out.category_id);
    TEST_ASSERT_EQUAL_UINT32(0xDDCCBBAAu, out.uid);
}

static void test_parse_short_buffer_returns_false(void)
{
    const uint8_t buf[7] = { 0 };
    ancs_notification_t out;
    TEST_ASSERT_FALSE(ancs_parse_notification_source(buf, sizeof(buf), &out));
    TEST_ASSERT_FALSE(ancs_parse_notification_source(NULL, 8, &out));
    TEST_ASSERT_FALSE(ancs_parse_notification_source(buf, 8, NULL));
}

/* ------------------------------------------------------------------ */
/* control point request builder                                       */
/* ------------------------------------------------------------------ */

static void test_build_get_title_request_layout(void)
{
    uint8_t out[16];
    size_t written = ancs_build_get_title_request(0xCAFEBABEu, 32, out, sizeof(out));

    TEST_ASSERT_EQUAL_size_t(8, written);
    TEST_ASSERT_EQUAL_UINT8(ANCS_CMD_GET_NOTIFICATION_ATTRIBUTES, out[0]);
    TEST_ASSERT_EQUAL_UINT8(0xBE, out[1]);
    TEST_ASSERT_EQUAL_UINT8(0xBA, out[2]);
    TEST_ASSERT_EQUAL_UINT8(0xFE, out[3]);
    TEST_ASSERT_EQUAL_UINT8(0xCA, out[4]);
    TEST_ASSERT_EQUAL_UINT8(ANCS_ATTR_TITLE, out[5]);
    TEST_ASSERT_EQUAL_UINT8(32, out[6]);
    TEST_ASSERT_EQUAL_UINT8(0, out[7]);
}

static void test_build_get_title_request_buffer_too_small(void)
{
    uint8_t out[4];
    TEST_ASSERT_EQUAL_size_t(0, ancs_build_get_title_request(0, 32, out, sizeof(out)));
    TEST_ASSERT_EQUAL_size_t(0, ancs_build_get_title_request(0, 32, NULL, 8));
}

/* ------------------------------------------------------------------ */
/* data source parsing                                                  */
/* ------------------------------------------------------------------ */

/* Build a Data Source response containing a single Title attribute.
 *   Layout: [cmd, uid_le32, attr_id, attr_len_le16, attr_data...] */
static size_t build_data_source_with_title(uint8_t *buf, uint32_t uid, const char *title)
{
    size_t title_len = strlen(title);
    buf[0] = (uint8_t)ANCS_CMD_GET_NOTIFICATION_ATTRIBUTES;
    buf[1] = (uint8_t)(uid & 0xFFu);
    buf[2] = (uint8_t)((uid >> 8) & 0xFFu);
    buf[3] = (uint8_t)((uid >> 16) & 0xFFu);
    buf[4] = (uint8_t)((uid >> 24) & 0xFFu);
    buf[5] = (uint8_t)ANCS_ATTR_TITLE;
    buf[6] = (uint8_t)(title_len & 0xFFu);
    buf[7] = (uint8_t)((title_len >> 8) & 0xFFu);
    memcpy(buf + 8, title, title_len);
    return 8 + title_len;
}

static void test_data_source_extracts_caller_name(void)
{
    uint8_t buf[64];
    size_t len = build_data_source_with_title(buf, 0x12345678u, "Mom");

    char title[32];
    bool ok = ancs_parse_data_source_title(buf, len, title, sizeof(title));

    TEST_ASSERT_TRUE(ok);
    TEST_ASSERT_EQUAL_STRING("Mom", title);
}

static void test_data_source_truncates_long_title(void)
{
    uint8_t buf[128];
    size_t len = build_data_source_with_title(buf, 0x1u, "ThisIsAVeryLongCallerNameWayTooLong");

    char title[16];
    TEST_ASSERT_TRUE(ancs_parse_data_source_title(buf, len, title, sizeof(title)));
    TEST_ASSERT_EQUAL_INT(15, (int)strlen(title));
}

static void test_data_source_skips_to_title_among_attributes(void)
{
    /* Build a response that includes a Subtitle attribute before Title. */
    uint8_t buf[64];
    buf[0] = (uint8_t)ANCS_CMD_GET_NOTIFICATION_ATTRIBUTES;
    buf[1] = 0x01;
    buf[2] = 0;
    buf[3] = 0;
    buf[4] = 0;

    /* Subtitle: id=2, len=4, "subt" */
    buf[5] = (uint8_t)ANCS_ATTR_SUBTITLE;
    buf[6] = 4;
    buf[7] = 0;
    memcpy(buf + 8, "subt", 4);

    /* Title: id=1, len=4, "Anna" */
    buf[12] = (uint8_t)ANCS_ATTR_TITLE;
    buf[13] = 4;
    buf[14] = 0;
    memcpy(buf + 15, "Anna", 4);

    char title[32];
    TEST_ASSERT_TRUE(ancs_parse_data_source_title(buf, 19, title, sizeof(title)));
    TEST_ASSERT_EQUAL_STRING("Anna", title);
}

static void test_data_source_no_title_returns_false(void)
{
    uint8_t buf[16];
    buf[0] = (uint8_t)ANCS_CMD_GET_NOTIFICATION_ATTRIBUTES;
    buf[1] = 0;
    buf[2] = 0;
    buf[3] = 0;
    buf[4] = 0;
    /* Subtitle only. */
    buf[5] = (uint8_t)ANCS_ATTR_SUBTITLE;
    buf[6] = 4;
    buf[7] = 0;
    memcpy(buf + 8, "test", 4);

    char title[32];
    TEST_ASSERT_FALSE(ancs_parse_data_source_title(buf, 12, title, sizeof(title)));
    TEST_ASSERT_EQUAL_STRING("", title);
}

static void test_data_source_wrong_command_returns_false(void)
{
    uint8_t buf[16] = { 0xFF, 0, 0, 0, 0, ANCS_ATTR_TITLE, 4, 0, 'A', 'n', 'n', 'a' };
    char title[32];
    TEST_ASSERT_FALSE(ancs_parse_data_source_title(buf, 12, title, sizeof(title)));
}

static void test_data_source_short_buffer_returns_false(void)
{
    uint8_t buf[4] = { 0 };
    char title[32];
    TEST_ASSERT_FALSE(ancs_parse_data_source_title(buf, sizeof(buf), title, sizeof(title)));
    TEST_ASSERT_FALSE(ancs_parse_data_source_title(NULL, 16, title, sizeof(title)));
    TEST_ASSERT_FALSE(ancs_parse_data_source_title(buf, 16, NULL, 32));
}

/* ------------------------------------------------------------------ */
/* main                                                                */
/* ------------------------------------------------------------------ */

int main(void)
{
    UNITY_BEGIN();

    RUN_TEST(test_parse_incoming_call_notification);
    RUN_TEST(test_parse_call_removed_notification);
    RUN_TEST(test_parse_missed_call_notification);
    RUN_TEST(test_parse_other_category_still_decodes);
    RUN_TEST(test_parse_short_buffer_returns_false);

    RUN_TEST(test_build_get_title_request_layout);
    RUN_TEST(test_build_get_title_request_buffer_too_small);

    RUN_TEST(test_data_source_extracts_caller_name);
    RUN_TEST(test_data_source_truncates_long_title);
    RUN_TEST(test_data_source_skips_to_title_among_attributes);
    RUN_TEST(test_data_source_no_title_returns_false);
    RUN_TEST(test_data_source_wrong_command_returns_false);
    RUN_TEST(test_data_source_short_buffer_returns_false);

    return UNITY_END();
}
