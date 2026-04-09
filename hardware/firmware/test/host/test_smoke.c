/*
 * Smoke test — proves the host Unity harness builds and runs on CI.
 *
 * Real tests land with each feature slice. This file must stay so that
 * the CI job has at least one green test to report while the codec and
 * FSM components are still empty.
 */

#include "unity.h"

void setUp(void) {}
void tearDown(void) {}

static void test_host_harness_runs(void)
{
    TEST_ASSERT_EQUAL_INT(4, 2 + 2);
}

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_host_harness_runs);
    return UNITY_END();
}
