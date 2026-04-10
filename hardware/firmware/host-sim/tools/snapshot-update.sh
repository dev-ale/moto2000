#!/usr/bin/env bash
#
# snapshot-update.sh — regenerate every golden PNG under
# hardware/firmware/host-sim/snapshots/ from the current renderer output.
#
# Run this only when an intentional UI change lands. Review the resulting
# diff visually before committing — the whole point of snapshot tests is
# to catch *unintentional* UI changes, so if this script is ever run
# without a human looking at the result, the net has a hole in it.
#
# Usage:
#   ./hardware/firmware/host-sim/tools/snapshot-update.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_SIM_DIR="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$HOST_SIM_DIR/../../.." && pwd)"
BUILD_DIR="$HOST_SIM_DIR/build"
FIXTURES_DIR="$REPO_ROOT/protocol/fixtures/valid"
SNAPSHOTS_DIR="$HOST_SIM_DIR/snapshots"

echo "==> configuring host-sim build"
cmake -S "$HOST_SIM_DIR" -B "$BUILD_DIR" >/dev/null
cmake --build "$BUILD_DIR" --target scramscreen-host-sim >/dev/null

SIM="$BUILD_DIR/scramscreen-host-sim"

# (name, fixture) pairs — mirror add_snapshot_test() in CMakeLists.txt.
SNAPSHOTS=(
    "clock_basel_winter              clock_basel_winter.bin"
    "clock_night_mode                clock_night_mode.bin"
    "compass_north_magnetic          compass_north_magnetic.bin"
    "compass_east_true               compass_east_true.bin"
    "compass_southwest_unknown_true  compass_southwest_unknown_true.bin"
    "speed_urban_45kmh               speed_urban_45kmh.bin"
    "speed_highway_120kmh            speed_highway_120kmh.bin"
    "speed_stationary                speed_stationary.bin"
    "nav_straight                    nav_straight.bin"
    "nav_sharp_left                  nav_sharp_left.bin"
    "nav_arrive                      nav_arrive.bin"
    "trip_stats_fresh                trip_stats_fresh.bin"
    "trip_stats_city_loop            trip_stats_city_loop.bin"
    "trip_stats_highway              trip_stats_highway.bin"
    "weather_basel_clear             weather_basel_clear.bin"
    "weather_alps_snow               weather_alps_snow.bin"
    "weather_paris_rain              weather_paris_rain.bin"
    "weather_cold_fog                weather_cold_fog.bin"
    "weather_thunderstorm            weather_thunderstorm.bin"
    "lean_upright                    lean_upright.bin"
    "lean_moderate_right             lean_moderate_right.bin"
    "lean_hard_left                  lean_hard_left.bin"
    "lean_racetrack                  lean_racetrack.bin"
    "music_playing                   music_playing.bin"
    "music_paused                    music_paused.bin"
    "music_long_titles               music_long_titles.bin"
    "music_unknown_duration          music_unknown_duration.bin"
    "appointment_soon                appointment_soon.bin"
    "appointment_now                 appointment_now.bin"
    "appointment_past                appointment_past.bin"
    "fuel_full_tank                  fuel_full_tank.bin"
    "fuel_half_tank                  fuel_half_tank.bin"
    "fuel_low                        fuel_low.bin"
    "altitude_flat                   altitude_flat.bin"
    "altitude_mountain_pass          altitude_mountain_pass.bin"
    "altitude_start                  altitude_start.bin"
    "call_incoming                   call_incoming.bin"
    "call_connected                  call_connected.bin"
    "call_ended                      call_ended.bin"
)

mkdir -p "$SNAPSHOTS_DIR"

for pair in "${SNAPSHOTS[@]}"; do
    # shellcheck disable=SC2206
    arr=($pair)
    name="${arr[0]}"
    fixture="${arr[1]}"
    out="$SNAPSHOTS_DIR/$name.png"
    echo "==> rendering $name ($fixture) -> $out"
    "$SIM" --in "$FIXTURES_DIR/$fixture" --out "$out"
done

echo "done. review 'git diff -- hardware/firmware/host-sim/snapshots/' before committing."
