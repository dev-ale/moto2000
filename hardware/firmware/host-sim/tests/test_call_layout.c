/*
 * test_call_layout.c — Unity tests for the call layout helper functions.
 */
#include "call_layout.h"
#include "unity.h"

#include <string.h>

void setUp(void) {}
void tearDown(void) {}

static void test_state_label_incoming(void)
{
    TEST_ASSERT_EQUAL_STRING("INCOMING CALL", call_state_label(BLE_CALL_INCOMING));
}

static void test_state_label_connected(void)
{
    TEST_ASSERT_EQUAL_STRING("CONNECTED", call_state_label(BLE_CALL_CONNECTED));
}

static void test_state_label_ended(void)
{
    TEST_ASSERT_EQUAL_STRING("ENDED", call_state_label(BLE_CALL_ENDED));
}

static void test_state_label_unknown(void)
{
    TEST_ASSERT_EQUAL_STRING("UNKNOWN", call_state_label((ble_call_state_t)0xFF));
}

static void test_avatar_initial_lowercase(void)
{
    TEST_ASSERT_EQUAL_CHAR('C', call_avatar_initial("contact-mom"));
}

static void test_avatar_initial_uppercase(void)
{
    TEST_ASSERT_EQUAL_CHAR('M', call_avatar_initial("Mom"));
}

static void test_avatar_initial_empty(void)
{
    TEST_ASSERT_EQUAL_CHAR('?', call_avatar_initial(""));
}

static void test_avatar_initial_null(void)
{
    TEST_ASSERT_EQUAL_CHAR('?', call_avatar_initial(NULL));
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_state_label_incoming);
    RUN_TEST(test_state_label_connected);
    RUN_TEST(test_state_label_ended);
    RUN_TEST(test_state_label_unknown);
    RUN_TEST(test_avatar_initial_lowercase);
    RUN_TEST(test_avatar_initial_uppercase);
    RUN_TEST(test_avatar_initial_empty);
    RUN_TEST(test_avatar_initial_null);
    return UNITY_END();
}
