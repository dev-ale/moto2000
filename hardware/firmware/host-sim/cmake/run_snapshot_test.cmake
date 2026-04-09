# run_snapshot_test.cmake — CTest driver for one snapshot test.
#
# Expected variables (all required, passed via -D on the command line):
#   SIM     — path to scramscreen-host-sim executable
#   DIFF    — path to snapshot-diff executable
#   FIXTURE — path to the input BLE payload .bin fixture
#   GOLDEN  — path to the committed golden PNG
#   OUT_DIR — directory to write the actual PNG into
#   NAME    — snapshot name (used for the output filename)

file(MAKE_DIRECTORY "${OUT_DIR}")
set(ACTUAL "${OUT_DIR}/${NAME}.png")

execute_process(
    COMMAND "${SIM}" --in "${FIXTURE}" --out "${ACTUAL}"
    RESULT_VARIABLE sim_rc
    OUTPUT_VARIABLE sim_stdout
    ERROR_VARIABLE  sim_stderr
)
if(NOT sim_rc EQUAL 0)
    message(FATAL_ERROR
        "host-sim failed for ${NAME} (rc=${sim_rc})\n"
        "stdout: ${sim_stdout}\n"
        "stderr: ${sim_stderr}")
endif()

if(NOT EXISTS "${GOLDEN}")
    message(FATAL_ERROR
        "Golden PNG missing for ${NAME}: ${GOLDEN}\n"
        "Run tools/snapshot-update.sh to create it, then review and commit.")
endif()

execute_process(
    COMMAND "${DIFF}" "${ACTUAL}" "${GOLDEN}"
    RESULT_VARIABLE diff_rc
    OUTPUT_VARIABLE diff_stdout
    ERROR_VARIABLE  diff_stderr
)
if(NOT diff_rc EQUAL 0)
    message(FATAL_ERROR
        "Snapshot ${NAME} does not match golden:\n"
        "  actual: ${ACTUAL}\n"
        "  golden: ${GOLDEN}\n"
        "${diff_stderr}\n"
        "If this is an intentional UI change, re-run tools/snapshot-update.sh")
endif()
