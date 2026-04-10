#!/usr/bin/env python3
"""
Generate BLE protocol golden fixtures.

This script is the *authoritative* source of truth for the bytes in the
`.bin` files under `valid/` and `invalid/`. Any change to the wire format in
`docs/ble-protocol.md` must be reflected here in the same commit as the
fixture regeneration.

Usage:
    cd protocol/fixtures
    python3 generate.py

The script reads every `.json` under `valid/` and `invalid/` and writes the
matching `.bin`. `valid/` fixtures describe well-formed packets. `invalid/`
fixtures carry a "raw_bytes" field whose hex value is written verbatim, used
by both codecs to prove malformed input is rejected.
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

PROTOCOL_VERSION = 0x01
HEADER_STRUCT = struct.Struct("<BBBBH")  # version, screen_id, flags, reserved, data_length
HEADER_SIZE = HEADER_STRUCT.size  # 6 bytes header + 2 bytes reserved pad? No — see below.

# The spec defines an 8-byte header: version, screen_id, flags, reserved,
# data_length (uint16). That's 1+1+1+1+2 = 6 bytes, plus 2 trailing reserved
# bytes to keep the body 4-byte-aligned. We encode that layout explicitly.
FULL_HEADER_STRUCT = struct.Struct("<BBBBHH")  # adds trailing reserved uint16 = 0
FULL_HEADER_SIZE = FULL_HEADER_STRUCT.size  # 8 bytes

SCREEN_IDS = {
    "navigation": 0x01,
    "speedHeading": 0x02,
    "compass": 0x03,
    "weather": 0x04,
    "tripStats": 0x05,
    "music": 0x06,
    "leanAngle": 0x07,
    "blitzer": 0x08,
    "incomingCall": 0x09,
    "fuelEstimate": 0x0A,
    "altitude": 0x0B,
    "appointment": 0x0C,
    "clock": 0x0D,
}

MANEUVER_TYPES = {
    "none": 0x00,
    "straight": 0x01,
    "slightLeft": 0x02,
    "left": 0x03,
    "sharpLeft": 0x04,
    "uTurnLeft": 0x05,
    "slightRight": 0x06,
    "right": 0x07,
    "sharpRight": 0x08,
    "uTurnRight": 0x09,
    "roundaboutEnter": 0x0A,
    "roundaboutExit": 0x0B,
    "merge": 0x0C,
    "forkLeft": 0x0D,
    "forkRight": 0x0E,
    "arrive": 0x0F,
}

FLAG_BITS = {
    "ALERT": 1 << 0,
    "NIGHT_MODE": 1 << 1,
    "STALE": 1 << 2,
}

NAV_BODY_SIZE = 56
CLOCK_BODY_SIZE = 12
SPEED_HEADING_BODY_SIZE = 8
COMPASS_BODY_SIZE = 8
TRIP_STATS_BODY_SIZE = 16
WEATHER_BODY_SIZE = 28
MUSIC_BODY_SIZE = 86

COMPASS_FLAG_USE_TRUE_HEADING = 1 << 0
COMPASS_TRUE_HEADING_UNKNOWN = 0xFFFF

WEATHER_CONDITIONS = {
    "clear": 0x00,
    "cloudy": 0x01,
    "rain": 0x02,
    "snow": 0x03,
    "fog": 0x04,
    "thunderstorm": 0x05,
}

LEAN_ANGLE_BODY_SIZE = 8
LEAN_ANGLE_MAX_ABS_X10 = 900

MUSIC_FLAG_PLAYING = 1 << 0
MUSIC_UNKNOWN_U16 = 0xFFFF
MUSIC_TITLE_LEN = 32
MUSIC_ARTIST_LEN = 24
MUSIC_ALBUM_LEN = 24

APPOINTMENT_BODY_SIZE = 60
APPOINTMENT_TITLE_LEN = 32
APPOINTMENT_LOCATION_LEN = 24

FUEL_BODY_SIZE = 8
FUEL_UNKNOWN_U16 = 0xFFFF

ALTITUDE_BODY_SIZE = 128
ALTITUDE_MAX_SAMPLES = 60

INCOMING_CALL_BODY_SIZE = 32
CALLER_HANDLE_FIELD_LEN = 30

BLITZER_BODY_SIZE = 8
BLITZER_CAMERA_TYPES = {
    "fixed": 0x00,
    "mobile": 0x01,
    "redLight": 0x02,
    "section": 0x03,
    "unknown": 0x04,
}
BLITZER_UNKNOWN_SPEED_LIMIT = 0xFFFF

CALL_STATES = {
    "incoming": 0x00,
    "connected": 0x01,
    "ended": 0x02,
}


def encode_flags(flags: list[str]) -> int:
    value = 0
    for name in flags:
        if name not in FLAG_BITS:
            raise ValueError(f"unknown flag: {name}")
        value |= FLAG_BITS[name]
    return value


def encode_fixed_string(value: str, length: int) -> bytes:
    data = value.encode("utf-8")
    if len(data) >= length:
        raise ValueError(
            f"string {value!r} is {len(data)} bytes, need < {length} to leave room for terminator"
        )
    return data + b"\x00" * (length - len(data))


def encode_header(screen_id: int, flags: int, body_length: int) -> bytes:
    return FULL_HEADER_STRUCT.pack(
        PROTOCOL_VERSION,
        screen_id,
        flags,
        0,  # reserved
        body_length,
        0,  # trailing reserved uint16
    )


def encode_clock_body(spec: dict) -> bytes:
    unix_time = int(spec["unix_time"])
    tz_offset = int(spec["tz_offset_minutes"])
    clock_flags = 0
    if spec.get("is_24h", True):
        clock_flags |= 0x01
    return struct.pack("<qhBB", unix_time, tz_offset, clock_flags, 0)


def encode_nav_body(spec: dict) -> bytes:
    lat_e7 = int(round(spec["lat"] * 1e7))
    lng_e7 = int(round(spec["lng"] * 1e7))
    speed_x10 = int(round(spec["speed_kmh"] * 10))
    heading_x10 = int(round(spec["heading_deg"] * 10))
    distance = spec.get("distance_to_maneuver_m", 0xFFFF)
    maneuver = MANEUVER_TYPES[spec["maneuver"]]
    street = encode_fixed_string(spec.get("street_name", ""), 32)
    eta = spec.get("eta_minutes", 0xFFFF)
    remaining_x10 = int(round(spec.get("remaining_km", 0) * 10)) if "remaining_km" in spec else 0xFFFF

    body = struct.pack(
        "<iiHHHBB",
        lat_e7,
        lng_e7,
        speed_x10,
        heading_x10,
        distance,
        maneuver,
        0,  # reserved
    )
    body += street
    body += struct.pack("<HHI", eta, remaining_x10, 0)  # eta, remaining, reserved2
    assert len(body) == NAV_BODY_SIZE, f"nav body is {len(body)} bytes, expected {NAV_BODY_SIZE}"
    return body


def encode_speed_heading_body(spec: dict) -> bytes:
    speed_x10 = int(round(spec["speed_kmh"] * 10))
    heading_x10 = int(round(spec["heading_deg"] * 10))
    altitude_m = int(round(spec["altitude_m"]))
    temperature_x10 = int(round(spec["temperature_celsius"] * 10))
    # <HHhh: uint16 speed, uint16 heading, int16 altitude, int16 temperature
    body = struct.pack("<HHhh", speed_x10, heading_x10, altitude_m, temperature_x10)
    assert len(body) == SPEED_HEADING_BODY_SIZE, (
        f"speed_heading body is {len(body)} bytes, expected {SPEED_HEADING_BODY_SIZE}"
    )
    return body


def encode_compass_body(spec: dict) -> bytes:
    magnetic_x10 = int(round(spec["magnetic_heading_deg"] * 10))
    if "true_heading_deg_raw" in spec:
        true_x10 = int(spec["true_heading_deg_raw"])
    elif "true_heading_deg" in spec:
        true_x10 = int(round(spec["true_heading_deg"] * 10))
    else:
        true_x10 = COMPASS_TRUE_HEADING_UNKNOWN
    accuracy_x10 = int(round(spec["heading_accuracy_deg"] * 10))
    compass_flags = 0
    if spec.get("use_true_heading", False):
        compass_flags |= COMPASS_FLAG_USE_TRUE_HEADING
    # <HHHBB: u16 magnetic, u16 true, u16 accuracy, u8 flags, u8 reserved
    body = struct.pack(
        "<HHHBB",
        magnetic_x10,
        true_x10,
        accuracy_x10,
        compass_flags,
        0,
    )
    assert len(body) == COMPASS_BODY_SIZE, (
        f"compass body is {len(body)} bytes, expected {COMPASS_BODY_SIZE}"
    )
    return body


def encode_trip_stats_body(spec: dict) -> bytes:
    ride_time = int(spec["ride_time_seconds"])
    distance = int(spec["distance_meters"])
    avg_x10 = int(round(spec["average_speed_kmh"] * 10))
    max_x10 = int(round(spec["max_speed_kmh"] * 10))
    ascent = int(spec["ascent_meters"])
    descent = int(spec["descent_meters"])
    body = struct.pack(
        "<IIHHHH",
        ride_time,
        distance,
        avg_x10,
        max_x10,
        ascent,
        descent,
    )
    assert len(body) == TRIP_STATS_BODY_SIZE, (
        f"trip_stats body is {len(body)} bytes, expected {TRIP_STATS_BODY_SIZE}"
    )
    return body


def encode_weather_body(spec: dict) -> bytes:
    condition_name = spec["condition"]
    if condition_name not in WEATHER_CONDITIONS:
        raise ValueError(f"unknown weather condition: {condition_name}")
    condition = WEATHER_CONDITIONS[condition_name]

    def temp_x10(key: str) -> int:
        if f"{key}_x10" in spec:
            return int(spec[f"{key}_x10"])
        return int(round(spec[key] * 10))

    temperature_x10 = temp_x10("temperature_celsius")
    high_x10 = temp_x10("high_celsius")
    low_x10 = temp_x10("low_celsius")
    name = encode_fixed_string(spec.get("location_name", ""), 20)
    body = struct.pack(
        "<BBhhh",
        condition,
        0,  # reserved
        temperature_x10,
        high_x10,
        low_x10,
    )
    body += name
    assert len(body) == WEATHER_BODY_SIZE, (
        f"weather body is {len(body)} bytes, expected {WEATHER_BODY_SIZE}"
    )
    return body


def encode_lean_angle_body(spec: dict) -> bytes:
    """Encode the 8-byte lean-angle body.

    Note: current_lean_deg_x10 is a signed int16. struct's "<h" handles
    two's-complement encoding for negative values automatically.
    """
    current_x10 = int(round(spec["current_lean_deg"] * 10))
    max_left_x10 = int(round(spec["max_left_lean_deg"] * 10))
    max_right_x10 = int(round(spec["max_right_lean_deg"] * 10))
    confidence = int(spec["confidence_percent"])
    # <hHHBB: int16 current, uint16 max_left, uint16 max_right, u8 conf, u8 reserved
    body = struct.pack(
        "<hHHBB",
        current_x10,
        max_left_x10,
        max_right_x10,
        confidence,
        0,
    )
    assert len(body) == LEAN_ANGLE_BODY_SIZE, (
        f"lean angle body is {len(body)} bytes, expected {LEAN_ANGLE_BODY_SIZE}"
    )
    return body


def encode_music_body(spec: dict) -> bytes:
    # Position and duration accept either the raw uint16 (for the 0xFFFF
    # sentinel) or the plain integer seconds.
    def u16_field(key: str) -> int:
        raw_key = f"{key}_raw"
        if raw_key in spec:
            return int(spec[raw_key]) & 0xFFFF
        return int(spec[key]) & 0xFFFF

    flags = 0
    if spec.get("is_playing", False):
        flags |= MUSIC_FLAG_PLAYING
    position = u16_field("position_seconds")
    duration = u16_field("duration_seconds")
    title = encode_fixed_string(spec.get("title", ""), MUSIC_TITLE_LEN)
    artist = encode_fixed_string(spec.get("artist", ""), MUSIC_ARTIST_LEN)
    album = encode_fixed_string(spec.get("album", ""), MUSIC_ALBUM_LEN)
    body = struct.pack("<BBHH", flags, 0, position, duration) + title + artist + album
    assert len(body) == MUSIC_BODY_SIZE, (
        f"music body is {len(body)} bytes, expected {MUSIC_BODY_SIZE}"
    )
    return body


def encode_appointment_body(spec: dict) -> bytes:
    starts_in_minutes = int(spec["starts_in_minutes"])
    title = encode_fixed_string(spec.get("title", ""), APPOINTMENT_TITLE_LEN)
    location = encode_fixed_string(spec.get("location", ""), APPOINTMENT_LOCATION_LEN)
    body = struct.pack("<h", starts_in_minutes) + title + location + struct.pack("<H", 0)
    assert len(body) == APPOINTMENT_BODY_SIZE, (
        f"appointment body is {len(body)} bytes, expected {APPOINTMENT_BODY_SIZE}"
    )
    return body


def encode_fuel_body(spec: dict) -> bytes:
    tank_percent = int(spec["tank_percent"])
    estimated_range_km = int(spec.get("estimated_range_km", FUEL_UNKNOWN_U16)) & 0xFFFF
    consumption_ml_per_km = int(spec.get("consumption_ml_per_km", FUEL_UNKNOWN_U16)) & 0xFFFF
    fuel_remaining_ml = int(spec.get("fuel_remaining_ml", FUEL_UNKNOWN_U16)) & 0xFFFF
    body = struct.pack(
        "<BBHHH",
        tank_percent,
        0,  # reserved
        estimated_range_km,
        consumption_ml_per_km,
        fuel_remaining_ml,
    )
    assert len(body) == FUEL_BODY_SIZE, (
        f"fuel body is {len(body)} bytes, expected {FUEL_BODY_SIZE}"
    )
    return body


def encode_altitude_body(spec: dict) -> bytes:
    current_altitude_m = int(spec["current_altitude_m"])
    total_ascent_m = int(spec["total_ascent_m"])
    total_descent_m = int(spec["total_descent_m"])
    profile = spec.get("profile", [])
    sample_count = int(spec.get("sample_count", len(profile)))
    # Header portion: int16 current_alt, uint16 ascent, uint16 descent, uint8 sample_count, uint8 reserved
    body = struct.pack(
        "<hHHBB",
        current_altitude_m,
        total_ascent_m,
        total_descent_m,
        sample_count,
        0,  # reserved
    )
    # Profile: 60 int16 values. Pad with zeros beyond the provided samples.
    padded_profile = list(profile) + [0] * (ALTITUDE_MAX_SAMPLES - len(profile))
    for i in range(ALTITUDE_MAX_SAMPLES):
        body += struct.pack("<h", int(padded_profile[i]))
    assert len(body) == ALTITUDE_BODY_SIZE, (
        f"altitude body is {len(body)} bytes, expected {ALTITUDE_BODY_SIZE}"
    )
    return body


def encode_incoming_call_body(spec: dict) -> bytes:
    state_name = spec["call_state"]
    if state_name not in CALL_STATES:
        raise ValueError(f"unknown call state: {state_name}")
    call_state = CALL_STATES[state_name]
    caller_handle = encode_fixed_string(spec.get("caller_handle", ""), CALLER_HANDLE_FIELD_LEN)
    body = struct.pack("<BB", call_state, 0) + caller_handle
    assert len(body) == INCOMING_CALL_BODY_SIZE, (
        f"incoming_call body is {len(body)} bytes, expected {INCOMING_CALL_BODY_SIZE}"
    )
    return body


def encode_blitzer_body(spec: dict) -> bytes:
    distance = int(spec["distance_meters"])
    if "speed_limit_kmh_raw" in spec:
        speed_limit = int(spec["speed_limit_kmh_raw"]) & 0xFFFF
    else:
        speed_limit = int(spec["speed_limit_kmh"]) & 0xFFFF
    current_speed_x10 = int(round(spec["current_speed_kmh"] * 10))
    camera_type_name = spec["camera_type"]
    if camera_type_name not in BLITZER_CAMERA_TYPES:
        raise ValueError(f"unknown camera type: {camera_type_name}")
    camera_type = BLITZER_CAMERA_TYPES[camera_type_name]
    body = struct.pack(
        "<HHHBB",
        distance,
        speed_limit,
        current_speed_x10,
        camera_type,
        0,  # reserved
    )
    assert len(body) == BLITZER_BODY_SIZE, (
        f"blitzer body is {len(body)} bytes, expected {BLITZER_BODY_SIZE}"
    )
    return body


BODY_ENCODERS = {
    "clock": encode_clock_body,
    "navigation": encode_nav_body,
    "speedHeading": encode_speed_heading_body,
    "compass": encode_compass_body,
    "tripStats": encode_trip_stats_body,
    "weather": encode_weather_body,
    "leanAngle": encode_lean_angle_body,
    "music": encode_music_body,
    "appointment": encode_appointment_body,
    "fuelEstimate": encode_fuel_body,
    "altitude": encode_altitude_body,
    "incomingCall": encode_incoming_call_body,
    "blitzer": encode_blitzer_body,
}


def encode_valid(spec: dict) -> bytes:
    screen = spec["screen"]
    screen_id = SCREEN_IDS[screen]
    flags = encode_flags(spec.get("flags", []))
    body = BODY_ENCODERS[screen](spec["body"])
    return encode_header(screen_id, flags, len(body)) + body


def encode_invalid(spec: dict) -> bytes:
    hex_string = spec["raw_bytes_hex"].replace(" ", "").replace("\n", "")
    return bytes.fromhex(hex_string)


# --------------------------------------------------------------------------- #
# Control characteristic (Slice 5)                                            #
# --------------------------------------------------------------------------- #

CONTROL_COMMANDS = {
    "setActiveScreen":   0x01,
    "setBrightness":     0x02,
    "sleep":             0x03,
    "wake":              0x04,
    "clearAlertOverlay": 0x05,
    "checkOTAUpdate":    0x06,
    "setScreenOrder":    0x07,
}

CONTROL_PAYLOAD_SIZE = 4


def encode_control_command(spec: dict) -> bytes:
    """Encode a control command per docs/ble-protocol.md §control commands.

    Layout (4 bytes): version, cmd, value0, value1. Commands without value
    bytes leave both value bytes zero.
    """
    name = spec["command"]
    if name not in CONTROL_COMMANDS:
        raise ValueError(f"unknown control command: {name}")
    cmd = CONTROL_COMMANDS[name]
    value0 = 0
    value1 = 0
    if name == "setActiveScreen":
        screen = spec["screen"]
        if screen not in SCREEN_IDS:
            raise ValueError(f"unknown screen for setActiveScreen: {screen}")
        value0 = SCREEN_IDS[screen]
    elif name == "setBrightness":
        value0 = int(spec["brightness"])
        if not (0 <= value0 <= 100):
            raise ValueError(f"brightness {value0} out of range 0..100")
    elif name == "setScreenOrder":
        screens = spec["screens"]
        screen_ids = []
        for s in screens:
            if s not in SCREEN_IDS:
                raise ValueError(f"unknown screen for setScreenOrder: {s}")
            screen_ids.append(SCREEN_IDS[s])
        return bytes([PROTOCOL_VERSION, cmd, len(screen_ids)] + screen_ids)
    return bytes([PROTOCOL_VERSION, cmd, value0, value1])


# --------------------------------------------------------------------------- #
# Status characteristic (Slice 21)                                            #
# --------------------------------------------------------------------------- #

STATUS_TYPES = {
    "screenChanged": 0x01,
}


def encode_status_message(spec: dict) -> bytes:
    """Encode a status notification per docs/ble-protocol.md."""
    name = spec["type"]
    if name not in STATUS_TYPES:
        raise ValueError(f"unknown status type: {name}")
    type_byte = STATUS_TYPES[name]
    if name == "screenChanged":
        screen = spec["screen"]
        if screen not in SCREEN_IDS:
            raise ValueError(f"unknown screen for screenChanged: {screen}")
        return bytes([PROTOCOL_VERSION, type_byte, SCREEN_IDS[screen]])
    raise ValueError(f"unhandled status type: {name}")


def process(directory: Path, encoder):
    count = 0
    for json_path in sorted(directory.glob("*.json")):
        with json_path.open() as f:
            spec = json.load(f)
        data = encoder(spec)
        bin_path = json_path.with_suffix(".bin")
        bin_path.write_bytes(data)
        count += 1
        print(f"  wrote {bin_path.relative_to(directory.parent)} ({len(data)} bytes)")
    return count


def main() -> int:
    root = Path(__file__).resolve().parent
    valid_dir = root / "valid"
    invalid_dir = root / "invalid"

    print("Regenerating BLE protocol fixtures")
    print("==================================")
    total = 0
    if valid_dir.exists():
        print(f"\n{valid_dir.relative_to(root.parent)}:")
        total += process(valid_dir, encode_valid)
    if invalid_dir.exists():
        print(f"\n{invalid_dir.relative_to(root.parent)}:")
        total += process(invalid_dir, encode_invalid)

    # Control characteristic fixtures live in their own subtree because the
    # wire format is different from screen_data.
    control_valid = root / "control" / "valid"
    control_invalid = root / "control" / "invalid"
    if control_valid.exists():
        print(f"\n{control_valid.relative_to(root.parent)}:")
        total += process(control_valid, encode_control_command)
    if control_invalid.exists():
        print(f"\n{control_invalid.relative_to(root.parent)}:")
        total += process(control_invalid, encode_invalid)

    # Status characteristic fixtures.
    status_valid = root / "status" / "valid"
    status_invalid = root / "status" / "invalid"
    if status_valid.exists():
        print(f"\n{status_valid.relative_to(root.parent)}:")
        total += process(status_valid, encode_status_message)
    if status_invalid.exists():
        print(f"\n{status_invalid.relative_to(root.parent)}:")
        total += process(status_invalid, encode_invalid)

    print(f"\nWrote {total} fixture(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
