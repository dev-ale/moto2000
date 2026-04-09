#!/usr/bin/env python3
"""
Generate replayable scenario JSON files from the supporting GPX + CSV
artefacts in this directory.

Running this script is the *authoritative* way to refresh the JSON. Never
hand-edit the .json files.

Usage:
    cd app/ios/Fixtures/scenarios
    python3 generate.py
"""
from __future__ import annotations

import csv
import json
import math
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

GPX_NS = {"gpx": "http://www.topografix.com/GPX/1/1"}
SCENARIO_VERSION = 1


def parse_gpx(path: Path) -> list[dict]:
    tree = ET.parse(path)
    root = tree.getroot()
    points = root.findall(".//gpx:trkpt", GPX_NS)
    samples: list[dict] = []
    first_time: datetime | None = None
    for point in points:
        lat = float(point.attrib["lat"])
        lon = float(point.attrib["lon"])
        ele_el = point.find("gpx:ele", GPX_NS)
        ele = float(ele_el.text) if ele_el is not None and ele_el.text else 0.0
        time_el = point.find("gpx:time", GPX_NS)
        when = datetime.fromisoformat(time_el.text.replace("Z", "+00:00")) if time_el is not None else None
        if when is not None and first_time is None:
            first_time = when
        scenario_time = (when - first_time).total_seconds() if (when and first_time) else float(len(samples))
        samples.append({
            "scenarioTime": scenario_time,
            "latitude": lat,
            "longitude": lon,
            "altitudeMeters": ele,
            "speedMps": -1,
            "courseDegrees": -1,
            "horizontalAccuracyMeters": 5,
        })
    # Compute speed and course from consecutive samples.
    for index in range(1, len(samples)):
        prev, curr = samples[index - 1], samples[index]
        dt = curr["scenarioTime"] - prev["scenarioTime"]
        if dt <= 0:
            continue
        dist = haversine_meters(prev["latitude"], prev["longitude"], curr["latitude"], curr["longitude"])
        curr["speedMps"] = dist / dt
        curr["courseDegrees"] = bearing_degrees(prev["latitude"], prev["longitude"], curr["latitude"], curr["longitude"])
    return samples


def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6_371_000
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * radius * math.asin(math.sqrt(h))


def bearing_degrees(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def parse_imu(path: Path) -> list[dict]:
    samples: list[dict] = []
    with path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            samples.append({
                "scenarioTime": float(row["scenarioTime"]),
                "gravityX": float(row["gravityX"]),
                "gravityY": float(row["gravityY"]),
                "gravityZ": float(row["gravityZ"]),
                "userAccelX": 0.0,
                "userAccelY": 0.0,
                "userAccelZ": 0.0,
            })
    return samples


def synthesize_headings(locations: list[dict]) -> list[dict]:
    headings: list[dict] = []
    for sample in locations:
        course = sample["courseDegrees"]
        if course < 0:
            continue
        headings.append({
            "scenarioTime": sample["scenarioTime"],
            "magneticDegrees": course,
            "trueDegrees": -1,
        })
    return headings


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


def build_basel_loop(root: Path) -> None:
    gpx = parse_gpx(root / "basel-city-loop.gpx")
    imu = parse_imu(root / "neutral-ride.imu.csv")
    scenario = {
        "version": SCENARIO_VERSION,
        "name": "basel-city-loop",
        "summary": "Short urban loop through central Basel with a mid-ride incoming call",
        "durationSeconds": 170.0,
        "locationSamples": gpx,
        "headingSamples": synthesize_headings(gpx),
        "motionSamples": imu,
        "weatherSnapshots": [
            {
                "scenarioTime": 0.0,
                "condition": "cloudy",
                "temperatureCelsius": 14.0,
                "highCelsius": 17.0,
                "lowCelsius": 9.0,
                "locationName": "Basel",
            },
        ],
        "nowPlayingSnapshots": [],
        "callEvents": [
            {"scenarioTime": 90.0, "state": "incoming", "callerHandle": "contact-mom"},
            {"scenarioTime": 110.0, "state": "ended", "callerHandle": "contact-mom"},
        ],
        "calendarEvents": [
            {
                "scenarioTime": 0.0,
                "title": "Meet at Kaffee Lade",
                "startsInSeconds": 1800.0,
                "location": "Kaffee Lade Basel",
            },
        ],
    }
    write_json(root / "basel-city-loop.json", scenario)


def build_highway(root: Path) -> None:
    gpx = parse_gpx(root / "highway-straight.gpx")
    scenario = {
        "version": SCENARIO_VERSION,
        "name": "highway-straight",
        "summary": "Steady highway run, clear weather, music playing",
        "durationSeconds": 120.0,
        "locationSamples": gpx,
        "headingSamples": synthesize_headings(gpx),
        "motionSamples": [],
        "weatherSnapshots": [
            {
                "scenarioTime": 0.0,
                "condition": "clear",
                "temperatureCelsius": 22.0,
                "highCelsius": 25.0,
                "lowCelsius": 13.0,
                "locationName": "Autobahn",
            },
        ],
        "nowPlayingSnapshots": [
            {
                "scenarioTime": 0.0,
                "title": "Moving On",
                "artist": "The Riders",
                "album": "Asphalt",
                "isPlaying": True,
                "positionSeconds": 0.0,
                "durationSeconds": 240.0,
            },
        ],
        "callEvents": [],
        "calendarEvents": [],
    }
    write_json(root / "highway-straight.json", scenario)


def build_twisty_mountain(root: Path) -> None:
    """Pure-motion scenario for the lean-angle screen.

    No GPS track — only IMU samples — so the integration test can replay
    a controlled lean profile through ScenarioPlayer + LeanAngleService
    without any location chatter.
    """
    imu = parse_imu(root / "twisty-mountain.imu.csv")
    scenario = {
        "version": SCENARIO_VERSION,
        "name": "twisty-mountain",
        "summary": "Pure motion scenario: alternating left/right leans up to 45° for the lean-angle screen",
        "durationSeconds": 30.0,
        "locationSamples": [],
        "headingSamples": [],
        "motionSamples": imu,
        "weatherSnapshots": [],
        "nowPlayingSnapshots": [],
        "callEvents": [],
        "calendarEvents": [],
    }
    write_json(root / "twisty-mountain.json", scenario)


def main() -> int:
    root = Path(__file__).resolve().parent
    print("Regenerating scenario fixtures")
    build_basel_loop(root)
    print("  wrote basel-city-loop.json")
    build_highway(root)
    print("  wrote highway-straight.json")
    build_twisty_mountain(root)
    print("  wrote twisty-mountain.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
