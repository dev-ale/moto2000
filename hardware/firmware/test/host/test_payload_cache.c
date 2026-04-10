/*
 * Host-side Unity tests for payload_cache.
 */
#include "payload_cache.h"
#include "unity.h"

#include <stdint.h>
#include <string.h>

#define NAV     ((uint8_t)0x01u)
#define COMPASS ((uint8_t)0x03u)
#define CLOCK   ((uint8_t)0x0Du)

void setUp(void) {}
void tearDown(void) {}

/* ----- init ------------------------------------------------------------- */

static void test_init_clears_all_slots(void)
{
    payload_cache_t cache;
    /* Fill with garbage first. */
    memset(&cache, 0xFF, sizeof(cache));
    payload_cache_init(&cache);

    for (uint8_t id = PAYLOAD_CACHE_MIN_SCREEN_ID; id <= PAYLOAD_CACHE_MAX_SCREEN_ID; id++) {
        TEST_ASSERT_FALSE(payload_cache_has(&cache, id));
    }
}

static void test_init_null_is_safe(void)
{
    payload_cache_init(NULL); /* must not crash */
}

/* ----- store and retrieve ----------------------------------------------- */

static void test_store_and_get(void)
{
    payload_cache_t cache;
    payload_cache_init(&cache);

    const uint8_t payload[] = { 0x01, 0x02, 0x03, 0x04, 0x05 };
    TEST_ASSERT_TRUE(payload_cache_store(&cache, NAV, payload, sizeof(payload)));
    TEST_ASSERT_TRUE(payload_cache_has(&cache, NAV));

    uint8_t out[256];
    size_t out_len = sizeof(out);
    TEST_ASSERT_TRUE(payload_cache_get(&cache, NAV, out, &out_len));
    TEST_ASSERT_EQUAL_size_t(sizeof(payload), out_len);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(payload, out, sizeof(payload));
}

static void test_overwrite_existing_payload(void)
{
    payload_cache_t cache;
    payload_cache_init(&cache);

    const uint8_t first[] = { 0xAA, 0xBB };
    const uint8_t second[] = { 0xCC, 0xDD, 0xEE };

    TEST_ASSERT_TRUE(payload_cache_store(&cache, COMPASS, first, sizeof(first)));
    TEST_ASSERT_TRUE(payload_cache_store(&cache, COMPASS, second, sizeof(second)));

    uint8_t out[256];
    size_t out_len = sizeof(out);
    TEST_ASSERT_TRUE(payload_cache_get(&cache, COMPASS, out, &out_len));
    TEST_ASSERT_EQUAL_size_t(sizeof(second), out_len);
    TEST_ASSERT_EQUAL_UINT8_ARRAY(second, out, sizeof(second));
}

static void test_empty_slot_returns_false(void)
{
    payload_cache_t cache;
    payload_cache_init(&cache);

    TEST_ASSERT_FALSE(payload_cache_has(&cache, CLOCK));

    uint8_t out[256];
    size_t out_len = sizeof(out);
    TEST_ASSERT_FALSE(payload_cache_get(&cache, CLOCK, out, &out_len));
}

static void test_all_13_slots_independent(void)
{
    payload_cache_t cache;
    payload_cache_init(&cache);

    /* Store a unique payload in each slot. */
    for (uint8_t id = PAYLOAD_CACHE_MIN_SCREEN_ID; id <= PAYLOAD_CACHE_MAX_SCREEN_ID; id++) {
        uint8_t payload[4];
        payload[0] = id;
        payload[1] = (uint8_t)(id * 2u);
        payload[2] = (uint8_t)(id * 3u);
        payload[3] = (uint8_t)(id * 4u);
        TEST_ASSERT_TRUE(payload_cache_store(&cache, id, payload, 4));
    }

    /* Verify each slot independently. */
    for (uint8_t id = PAYLOAD_CACHE_MIN_SCREEN_ID; id <= PAYLOAD_CACHE_MAX_SCREEN_ID; id++) {
        TEST_ASSERT_TRUE(payload_cache_has(&cache, id));

        uint8_t out[256];
        size_t out_len = sizeof(out);
        TEST_ASSERT_TRUE(payload_cache_get(&cache, id, out, &out_len));
        TEST_ASSERT_EQUAL_size_t(4, out_len);
        TEST_ASSERT_EQUAL_UINT8(id, out[0]);
        TEST_ASSERT_EQUAL_UINT8((uint8_t)(id * 2u), out[1]);
        TEST_ASSERT_EQUAL_UINT8((uint8_t)(id * 3u), out[2]);
        TEST_ASSERT_EQUAL_UINT8((uint8_t)(id * 4u), out[3]);
    }
}

/* ----- edge cases ------------------------------------------------------- */

static void test_invalid_screen_id_rejected(void)
{
    payload_cache_t cache;
    payload_cache_init(&cache);

    const uint8_t payload[] = { 0x01 };
    TEST_ASSERT_FALSE(payload_cache_store(&cache, 0x00, payload, 1));
    TEST_ASSERT_FALSE(payload_cache_store(&cache, 0x0E, payload, 1));
    TEST_ASSERT_FALSE(payload_cache_store(&cache, 0xFF, payload, 1));

    TEST_ASSERT_FALSE(payload_cache_has(&cache, 0x00));
    TEST_ASSERT_FALSE(payload_cache_has(&cache, 0x0E));
}

static void test_zero_length_rejected(void)
{
    payload_cache_t cache;
    payload_cache_init(&cache);

    const uint8_t payload[] = { 0x01 };
    TEST_ASSERT_FALSE(payload_cache_store(&cache, NAV, payload, 0));
}

static void test_oversized_payload_rejected(void)
{
    payload_cache_t cache;
    payload_cache_init(&cache);

    uint8_t big[257];
    memset(big, 0xAA, sizeof(big));
    TEST_ASSERT_FALSE(payload_cache_store(&cache, NAV, big, sizeof(big)));
}

static void test_null_pointers_rejected(void)
{
    payload_cache_t cache;
    payload_cache_init(&cache);

    const uint8_t payload[] = { 0x01 };
    TEST_ASSERT_FALSE(payload_cache_store(NULL, NAV, payload, 1));
    TEST_ASSERT_FALSE(payload_cache_store(&cache, NAV, NULL, 1));
    TEST_ASSERT_FALSE(payload_cache_has(NULL, NAV));
    TEST_ASSERT_FALSE(payload_cache_get(NULL, NAV, NULL, NULL));

    uint8_t out[16];
    size_t out_len = sizeof(out);
    TEST_ASSERT_FALSE(payload_cache_get(&cache, NAV, NULL, &out_len));
    TEST_ASSERT_FALSE(payload_cache_get(&cache, NAV, out, NULL));
}

static void test_get_truncates_to_output_buffer(void)
{
    payload_cache_t cache;
    payload_cache_init(&cache);

    const uint8_t payload[] = { 0x01, 0x02, 0x03, 0x04, 0x05 };
    payload_cache_store(&cache, NAV, payload, sizeof(payload));

    uint8_t out[3];
    size_t out_len = sizeof(out);
    TEST_ASSERT_TRUE(payload_cache_get(&cache, NAV, out, &out_len));
    /* out_len reports the real size, but only 3 bytes were copied. */
    TEST_ASSERT_EQUAL_size_t(sizeof(payload), out_len);
    TEST_ASSERT_EQUAL_UINT8(0x01, out[0]);
    TEST_ASSERT_EQUAL_UINT8(0x02, out[1]);
    TEST_ASSERT_EQUAL_UINT8(0x03, out[2]);
}

/* ----------------------------------------------------------------------- */

int main(void)
{
    UNITY_BEGIN();

    RUN_TEST(test_init_clears_all_slots);
    RUN_TEST(test_init_null_is_safe);
    RUN_TEST(test_store_and_get);
    RUN_TEST(test_overwrite_existing_payload);
    RUN_TEST(test_empty_slot_returns_false);
    RUN_TEST(test_all_13_slots_independent);
    RUN_TEST(test_invalid_screen_id_rejected);
    RUN_TEST(test_zero_length_rejected);
    RUN_TEST(test_oversized_payload_rejected);
    RUN_TEST(test_null_pointers_rejected);
    RUN_TEST(test_get_truncates_to_output_buffer);

    return UNITY_END();
}
