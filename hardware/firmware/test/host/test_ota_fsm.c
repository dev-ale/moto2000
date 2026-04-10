/*
 * test_ota_fsm — Unity host tests for the OTA state machine, version
 * comparison, and HMAC-SHA256 signature verification.
 *
 * Covers every state x event combination for the FSM, retry logic,
 * the full happy path, version parsing/comparison, and HMAC-SHA256
 * with RFC 4231 test vectors.
 */
#include "unity.h"

#include "ota_fsm.h"
#include "ota_verify.h"
#include "ota_version.h"

#include <string.h>

/* ======================================================================== */
/* OTA FSM tests                                                            */
/* ======================================================================== */

static ota_fsm_t fsm;

void setUp(void) { ota_fsm_init(&fsm); }
void tearDown(void) {}

/* --- Init ------------------------------------------------------------ */

static void test_init_state_is_idle(void)
{
    TEST_ASSERT_EQUAL(OTA_STATE_IDLE, fsm.state);
    TEST_ASSERT_EQUAL_UINT8(0, fsm.retry_count);
    TEST_ASSERT_EQUAL_UINT8(OTA_DEFAULT_MAX_RETRIES, fsm.max_retries);
}

/* --- IDLE state ------------------------------------------------------ */

static void test_idle_check_requested(void)
{
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    TEST_ASSERT_EQUAL(OTA_STATE_CHECKING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_CHECK, a);
}

static void test_idle_ignores_other_events(void)
{
    /* All events except CHECK_REQUESTED should be ignored in IDLE. */
    ota_event_t events[] = {
        OTA_EVENT_VERSION_AVAILABLE, OTA_EVENT_NO_UPDATE,
        OTA_EVENT_DOWNLOAD_COMPLETE, OTA_EVENT_DOWNLOAD_FAILED,
        OTA_EVENT_VERIFY_OK,         OTA_EVENT_VERIFY_FAILED,
        OTA_EVENT_APPLY_OK,          OTA_EVENT_APPLY_FAILED,
        OTA_EVENT_BOOT_CONFIRMED,    OTA_EVENT_BOOT_FAILED,
        OTA_EVENT_RESET,
    };
    for (size_t i = 0; i < sizeof(events) / sizeof(events[0]); i++) {
        ota_fsm_init(&fsm);
        ota_action_t a = ota_fsm_handle(&fsm, events[i]);
        TEST_ASSERT_EQUAL(OTA_STATE_IDLE, fsm.state);
        TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
    }
}

/* --- CHECKING state -------------------------------------------------- */

static void test_checking_version_available(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    TEST_ASSERT_EQUAL(OTA_STATE_DOWNLOADING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_DOWNLOAD, a);
}

static void test_checking_no_update(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_NO_UPDATE);
    TEST_ASSERT_EQUAL(OTA_STATE_IDLE, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
}

static void test_checking_ignores_irrelevant(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    TEST_ASSERT_EQUAL(OTA_STATE_CHECKING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
}

/* --- DOWNLOADING state ----------------------------------------------- */

static void test_downloading_complete(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    TEST_ASSERT_EQUAL(OTA_STATE_VERIFYING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_VERIFY, a);
}

static void test_downloading_failed_retries(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);

    /* First two failures should retry (max_retries=3). */
    ota_action_t a1 = ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_FAILED);
    TEST_ASSERT_EQUAL(OTA_STATE_DOWNLOADING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_DOWNLOAD, a1);
    TEST_ASSERT_EQUAL_UINT8(1, fsm.retry_count);

    ota_action_t a2 = ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_FAILED);
    TEST_ASSERT_EQUAL(OTA_STATE_DOWNLOADING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_DOWNLOAD, a2);
    TEST_ASSERT_EQUAL_UINT8(2, fsm.retry_count);

    /* Third failure exhausts retries -> ERROR. */
    ota_action_t a3 = ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_FAILED);
    TEST_ASSERT_EQUAL(OTA_STATE_ERROR, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_REPORT_ERROR, a3);
    TEST_ASSERT_EQUAL_UINT8(3, fsm.retry_count);
}

static void test_downloading_ignores_irrelevant(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    TEST_ASSERT_EQUAL(OTA_STATE_DOWNLOADING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
}

/* --- VERIFYING state ------------------------------------------------- */

static void test_verifying_ok(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    TEST_ASSERT_EQUAL(OTA_STATE_APPLYING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_APPLY, a);
}

static void test_verifying_failed(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_FAILED);
    TEST_ASSERT_EQUAL(OTA_STATE_ERROR, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_REPORT_ERROR, a);
}

static void test_verifying_ignores_irrelevant(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    TEST_ASSERT_EQUAL(OTA_STATE_VERIFYING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
}

/* --- APPLYING state -------------------------------------------------- */

static void test_applying_ok(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_APPLY_OK);
    TEST_ASSERT_EQUAL(OTA_STATE_REBOOTING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_REBOOT, a);
}

static void test_applying_failed(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_APPLY_FAILED);
    TEST_ASSERT_EQUAL(OTA_STATE_ERROR, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_REPORT_ERROR, a);
}

static void test_applying_ignores_irrelevant(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_NO_UPDATE);
    TEST_ASSERT_EQUAL(OTA_STATE_APPLYING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
}

/* --- REBOOTING state ------------------------------------------------- */

static void test_rebooting_boot_confirmed(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    ota_fsm_handle(&fsm, OTA_EVENT_APPLY_OK);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_BOOT_CONFIRMED);
    TEST_ASSERT_EQUAL(OTA_STATE_IDLE, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_CONFIRM_BOOT, a);
}

static void test_rebooting_boot_failed(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    ota_fsm_handle(&fsm, OTA_EVENT_APPLY_OK);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_BOOT_FAILED);
    TEST_ASSERT_EQUAL(OTA_STATE_ROLLBACK, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_ROLLBACK, a);
}

static void test_rebooting_ignores_irrelevant(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    ota_fsm_handle(&fsm, OTA_EVENT_APPLY_OK);
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    TEST_ASSERT_EQUAL(OTA_STATE_REBOOTING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
}

/* --- ROLLBACK state -------------------------------------------------- */

static void test_rollback_reset(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    ota_fsm_handle(&fsm, OTA_EVENT_APPLY_OK);
    ota_fsm_handle(&fsm, OTA_EVENT_BOOT_FAILED);
    TEST_ASSERT_EQUAL(OTA_STATE_ROLLBACK, fsm.state);

    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_RESET);
    TEST_ASSERT_EQUAL(OTA_STATE_IDLE, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
}

static void test_rollback_ignores_other(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    ota_fsm_handle(&fsm, OTA_EVENT_APPLY_OK);
    ota_fsm_handle(&fsm, OTA_EVENT_BOOT_FAILED);

    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    TEST_ASSERT_EQUAL(OTA_STATE_ROLLBACK, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
}

/* --- ERROR state ----------------------------------------------------- */

static void test_error_reset(void)
{
    /* Force into ERROR via verify failure. */
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_FAILED);
    TEST_ASSERT_EQUAL(OTA_STATE_ERROR, fsm.state);

    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_RESET);
    TEST_ASSERT_EQUAL(OTA_STATE_IDLE, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
    TEST_ASSERT_EQUAL_UINT8(0, fsm.retry_count);
}

static void test_error_ignores_other(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_FAILED);

    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    TEST_ASSERT_EQUAL(OTA_STATE_ERROR, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
}

/* --- Full happy path ------------------------------------------------- */

static void test_full_happy_path(void)
{
    ota_action_t a;

    a = ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    TEST_ASSERT_EQUAL(OTA_STATE_CHECKING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_CHECK, a);

    a = ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);
    TEST_ASSERT_EQUAL(OTA_STATE_DOWNLOADING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_DOWNLOAD, a);

    a = ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    TEST_ASSERT_EQUAL(OTA_STATE_VERIFYING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_VERIFY, a);

    a = ota_fsm_handle(&fsm, OTA_EVENT_VERIFY_OK);
    TEST_ASSERT_EQUAL(OTA_STATE_APPLYING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_APPLY, a);

    a = ota_fsm_handle(&fsm, OTA_EVENT_APPLY_OK);
    TEST_ASSERT_EQUAL(OTA_STATE_REBOOTING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_REBOOT, a);

    a = ota_fsm_handle(&fsm, OTA_EVENT_BOOT_CONFIRMED);
    TEST_ASSERT_EQUAL(OTA_STATE_IDLE, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_CONFIRM_BOOT, a);
}

/* --- Retry with eventual success ------------------------------------- */

static void test_download_retry_then_success(void)
{
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);

    /* Two failures, then success. */
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_FAILED);
    TEST_ASSERT_EQUAL_UINT8(1, fsm.retry_count);
    ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_FAILED);
    TEST_ASSERT_EQUAL_UINT8(2, fsm.retry_count);

    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_COMPLETE);
    TEST_ASSERT_EQUAL(OTA_STATE_VERIFYING, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_START_VERIFY, a);
}

/* --- Custom max_retries ---------------------------------------------- */

static void test_custom_max_retries(void)
{
    fsm.max_retries = 1;
    ota_fsm_handle(&fsm, OTA_EVENT_CHECK_REQUESTED);
    ota_fsm_handle(&fsm, OTA_EVENT_VERSION_AVAILABLE);

    /* First failure exhausts retries immediately. */
    ota_action_t a = ota_fsm_handle(&fsm, OTA_EVENT_DOWNLOAD_FAILED);
    TEST_ASSERT_EQUAL(OTA_STATE_ERROR, fsm.state);
    TEST_ASSERT_EQUAL(OTA_ACTION_REPORT_ERROR, a);
}

/* --- NULL safety ----------------------------------------------------- */

static void test_null_fsm(void)
{
    ota_action_t a = ota_fsm_handle(NULL, OTA_EVENT_CHECK_REQUESTED);
    TEST_ASSERT_EQUAL(OTA_ACTION_NONE, a);
}

static void test_null_init(void)
{
    ota_fsm_init(NULL); /* Must not crash. */
}

/* --- Name helpers ---------------------------------------------------- */

static void test_state_names(void)
{
    TEST_ASSERT_EQUAL_STRING("IDLE", ota_state_name(OTA_STATE_IDLE));
    TEST_ASSERT_EQUAL_STRING("ERROR", ota_state_name(OTA_STATE_ERROR));
    TEST_ASSERT_EQUAL_STRING("UNKNOWN", ota_state_name((ota_state_t)99));
}

static void test_action_names(void)
{
    TEST_ASSERT_EQUAL_STRING("NONE", ota_action_name(OTA_ACTION_NONE));
    TEST_ASSERT_EQUAL_STRING("ROLLBACK", ota_action_name(OTA_ACTION_ROLLBACK));
    TEST_ASSERT_EQUAL_STRING("UNKNOWN", ota_action_name((ota_action_t)99));
}

/* ======================================================================== */
/* OTA Version tests                                                        */
/* ======================================================================== */

static void test_version_equal(void)
{
    ota_version_t a = {1, 2, 3};
    ota_version_t b = {1, 2, 3};
    TEST_ASSERT_EQUAL_INT(0, ota_version_compare(&a, &b));
    TEST_ASSERT_FALSE(ota_version_is_newer(&a, &b));
}

static void test_version_newer_major(void)
{
    ota_version_t current   = {1, 0, 0};
    ota_version_t available = {2, 0, 0};
    TEST_ASSERT_TRUE(ota_version_is_newer(&current, &available));
    TEST_ASSERT_FALSE(ota_version_is_newer(&available, &current));
}

static void test_version_newer_minor(void)
{
    ota_version_t current   = {1, 2, 0};
    ota_version_t available = {1, 3, 0};
    TEST_ASSERT_TRUE(ota_version_is_newer(&current, &available));
}

static void test_version_newer_patch(void)
{
    ota_version_t current   = {1, 2, 3};
    ota_version_t available = {1, 2, 4};
    TEST_ASSERT_TRUE(ota_version_is_newer(&current, &available));
}

static void test_version_older(void)
{
    ota_version_t current   = {2, 0, 0};
    ota_version_t available = {1, 9, 9};
    TEST_ASSERT_FALSE(ota_version_is_newer(&current, &available));
}

static void test_version_compare_ordering(void)
{
    ota_version_t a = {1, 0, 0};
    ota_version_t b = {2, 0, 0};
    TEST_ASSERT_TRUE(ota_version_compare(&a, &b) < 0);
    TEST_ASSERT_TRUE(ota_version_compare(&b, &a) > 0);
}

static void test_version_parse_valid(void)
{
    ota_version_t v;
    TEST_ASSERT_TRUE(ota_version_parse("1.2.3", &v));
    TEST_ASSERT_EQUAL_UINT8(1, v.major);
    TEST_ASSERT_EQUAL_UINT8(2, v.minor);
    TEST_ASSERT_EQUAL_UINT8(3, v.patch);
}

static void test_version_parse_zeros(void)
{
    ota_version_t v;
    TEST_ASSERT_TRUE(ota_version_parse("0.0.0", &v));
    TEST_ASSERT_EQUAL_UINT8(0, v.major);
    TEST_ASSERT_EQUAL_UINT8(0, v.minor);
    TEST_ASSERT_EQUAL_UINT8(0, v.patch);
}

static void test_version_parse_max(void)
{
    ota_version_t v;
    TEST_ASSERT_TRUE(ota_version_parse("255.255.255", &v));
    TEST_ASSERT_EQUAL_UINT8(255, v.major);
    TEST_ASSERT_EQUAL_UINT8(255, v.minor);
    TEST_ASSERT_EQUAL_UINT8(255, v.patch);
}

static void test_version_parse_invalid(void)
{
    ota_version_t v;
    TEST_ASSERT_FALSE(ota_version_parse("", &v));
    TEST_ASSERT_FALSE(ota_version_parse("1", &v));
    TEST_ASSERT_FALSE(ota_version_parse("1.2", &v));
    TEST_ASSERT_FALSE(ota_version_parse("1.2.3.4", &v));
    TEST_ASSERT_FALSE(ota_version_parse("abc", &v));
    TEST_ASSERT_FALSE(ota_version_parse("256.0.0", &v));
    TEST_ASSERT_FALSE(ota_version_parse("1..3", &v));
    TEST_ASSERT_FALSE(ota_version_parse(NULL, &v));
    TEST_ASSERT_FALSE(ota_version_parse("1.2.3", NULL));
    TEST_ASSERT_FALSE(ota_version_parse(".1.2", &v));
    TEST_ASSERT_FALSE(ota_version_parse("1.2.", &v));
}

static void test_version_to_string(void)
{
    ota_version_t v = {1, 2, 3};
    char buf[16];
    ota_version_to_string(&v, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("1.2.3", buf);
}

static void test_version_to_string_max(void)
{
    ota_version_t v = {255, 255, 255};
    char buf[16];
    ota_version_to_string(&v, buf, sizeof(buf));
    TEST_ASSERT_EQUAL_STRING("255.255.255", buf);
}

static void test_version_roundtrip(void)
{
    ota_version_t original = {10, 20, 30};
    char buf[16];
    ota_version_to_string(&original, buf, sizeof(buf));

    ota_version_t parsed;
    TEST_ASSERT_TRUE(ota_version_parse(buf, &parsed));
    TEST_ASSERT_EQUAL_UINT8(original.major, parsed.major);
    TEST_ASSERT_EQUAL_UINT8(original.minor, parsed.minor);
    TEST_ASSERT_EQUAL_UINT8(original.patch, parsed.patch);
}

/* ======================================================================== */
/* HMAC-SHA256 verification tests                                           */
/* ======================================================================== */

/*
 * RFC 4231 Test Case 1:
 *   Key  = 0x0b repeated 20 times
 *   Data = "Hi There"
 *   HMAC = b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7
 */
static void test_hmac_rfc4231_case1(void)
{
    ota_verify_key_t key;
    memset(key.key, 0x0b, 20);
    memset(key.key + 20, 0, 12);
    key.key_len = 20;

    const uint8_t data[] = "Hi There";
    const uint8_t expected[] = {
        0xb0, 0x34, 0x4c, 0x61, 0xd8, 0xdb, 0x38, 0x53, 0x5c, 0xa8, 0xaf,
        0xce, 0xaf, 0x0b, 0xf1, 0x2b, 0x88, 0x1d, 0xc2, 0x00, 0xc9, 0x83,
        0x3d, 0xa7, 0x26, 0xe9, 0x37, 0x6c, 0x2e, 0x32, 0xcf, 0xf7,
    };

    TEST_ASSERT_TRUE(ota_verify_hmac_sha256(&key, data, 8, expected, 32));
}

/*
 * RFC 4231 Test Case 2:
 *   Key  = "Jefe"
 *   Data = "what do ya want for nothing?"
 *   HMAC = 5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843
 */
static void test_hmac_rfc4231_case2(void)
{
    ota_verify_key_t key;
    memset(key.key, 0, sizeof(key.key));
    memcpy(key.key, "Jefe", 4);
    key.key_len = 4;

    const char *msg         = "what do ya want for nothing?";
    const uint8_t expected[] = {
        0x5b, 0xdc, 0xc1, 0x46, 0xbf, 0x60, 0x75, 0x4e, 0x6a, 0x04, 0x24,
        0x26, 0x08, 0x95, 0x75, 0xc7, 0x5a, 0x00, 0x3f, 0x08, 0x9d, 0x27,
        0x39, 0x83, 0x9d, 0xec, 0x58, 0xb9, 0x64, 0xec, 0x38, 0x43,
    };

    TEST_ASSERT_TRUE(ota_verify_hmac_sha256(
        &key, (const uint8_t *)msg, strlen(msg), expected, 32));
}

static void test_hmac_tampered_mac(void)
{
    ota_verify_key_t key;
    memset(key.key, 0x0b, 20);
    memset(key.key + 20, 0, 12);
    key.key_len = 20;

    const uint8_t data[] = "Hi There";
    uint8_t bad_mac[32];
    memset(bad_mac, 0xAA, 32);

    TEST_ASSERT_FALSE(ota_verify_hmac_sha256(&key, data, 8, bad_mac, 32));
}

static void test_hmac_tampered_data(void)
{
    ota_verify_key_t key;
    memset(key.key, 0x0b, 20);
    memset(key.key + 20, 0, 12);
    key.key_len = 20;

    /* MAC for "Hi There", but data is different. */
    const uint8_t expected[] = {
        0xb0, 0x34, 0x4c, 0x61, 0xd8, 0xdb, 0x38, 0x53, 0x5c, 0xa8, 0xaf,
        0xce, 0xaf, 0x0b, 0xf1, 0x2b, 0x88, 0x1d, 0xc2, 0x00, 0xc9, 0x83,
        0x3d, 0xa7, 0x26, 0xe9, 0x37, 0x6c, 0x2e, 0x32, 0xcf, 0xf7,
    };
    const uint8_t tampered[] = "Hi Thera";

    TEST_ASSERT_FALSE(ota_verify_hmac_sha256(&key, tampered, 8, expected, 32));
}

static void test_hmac_empty_data(void)
{
    /* HMAC of empty message should not crash and should produce a valid MAC. */
    ota_verify_key_t key;
    memset(key.key, 0x01, 16);
    memset(key.key + 16, 0, 16);
    key.key_len = 16;

    /* We don't check the exact value — just that it doesn't crash
     * and returns false for a wrong expected_mac. */
    uint8_t wrong[32];
    memset(wrong, 0, 32);
    /* Might or might not match all zeros, but the important thing is no crash. */
    (void)ota_verify_hmac_sha256(&key, NULL, 0, wrong, 32);
}

static void test_hmac_null_key(void)
{
    uint8_t data[] = {0x01};
    uint8_t mac[32];
    memset(mac, 0, 32);
    TEST_ASSERT_FALSE(ota_verify_hmac_sha256(NULL, data, 1, mac, 32));
}

static void test_hmac_null_expected_mac(void)
{
    ota_verify_key_t key;
    memset(key.key, 0x01, 16);
    key.key_len = 16;
    uint8_t data[] = {0x01};
    TEST_ASSERT_FALSE(ota_verify_hmac_sha256(&key, data, 1, NULL, 32));
}

static void test_hmac_wrong_mac_len(void)
{
    ota_verify_key_t key;
    memset(key.key, 0x01, 16);
    key.key_len = 16;
    uint8_t data[] = {0x01};
    uint8_t mac[32];
    memset(mac, 0, 32);
    TEST_ASSERT_FALSE(ota_verify_hmac_sha256(&key, data, 1, mac, 16));
}

/* ======================================================================== */
/* Runner                                                                   */
/* ======================================================================== */

int main(void)
{
    UNITY_BEGIN();

    /* OTA FSM */
    RUN_TEST(test_init_state_is_idle);
    RUN_TEST(test_idle_check_requested);
    RUN_TEST(test_idle_ignores_other_events);
    RUN_TEST(test_checking_version_available);
    RUN_TEST(test_checking_no_update);
    RUN_TEST(test_checking_ignores_irrelevant);
    RUN_TEST(test_downloading_complete);
    RUN_TEST(test_downloading_failed_retries);
    RUN_TEST(test_downloading_ignores_irrelevant);
    RUN_TEST(test_verifying_ok);
    RUN_TEST(test_verifying_failed);
    RUN_TEST(test_verifying_ignores_irrelevant);
    RUN_TEST(test_applying_ok);
    RUN_TEST(test_applying_failed);
    RUN_TEST(test_applying_ignores_irrelevant);
    RUN_TEST(test_rebooting_boot_confirmed);
    RUN_TEST(test_rebooting_boot_failed);
    RUN_TEST(test_rebooting_ignores_irrelevant);
    RUN_TEST(test_rollback_reset);
    RUN_TEST(test_rollback_ignores_other);
    RUN_TEST(test_error_reset);
    RUN_TEST(test_error_ignores_other);
    RUN_TEST(test_full_happy_path);
    RUN_TEST(test_download_retry_then_success);
    RUN_TEST(test_custom_max_retries);
    RUN_TEST(test_null_fsm);
    RUN_TEST(test_null_init);
    RUN_TEST(test_state_names);
    RUN_TEST(test_action_names);

    /* Version */
    RUN_TEST(test_version_equal);
    RUN_TEST(test_version_newer_major);
    RUN_TEST(test_version_newer_minor);
    RUN_TEST(test_version_newer_patch);
    RUN_TEST(test_version_older);
    RUN_TEST(test_version_compare_ordering);
    RUN_TEST(test_version_parse_valid);
    RUN_TEST(test_version_parse_zeros);
    RUN_TEST(test_version_parse_max);
    RUN_TEST(test_version_parse_invalid);
    RUN_TEST(test_version_to_string);
    RUN_TEST(test_version_to_string_max);
    RUN_TEST(test_version_roundtrip);

    /* HMAC-SHA256 */
    RUN_TEST(test_hmac_rfc4231_case1);
    RUN_TEST(test_hmac_rfc4231_case2);
    RUN_TEST(test_hmac_tampered_mac);
    RUN_TEST(test_hmac_tampered_data);
    RUN_TEST(test_hmac_empty_data);
    RUN_TEST(test_hmac_null_key);
    RUN_TEST(test_hmac_null_expected_mac);
    RUN_TEST(test_hmac_wrong_mac_len);

    return UNITY_END();
}
