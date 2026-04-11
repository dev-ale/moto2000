#!/usr/bin/env python3
"""Fetch speed camera data from OpenStreetMap and write to SQLite.

Queries the Overpass API for highway=speed_camera nodes within
Switzerland and neighboring border areas (DE, AT, IT, FR within ~50km),
then writes a SQLite database with a `cameras` table suitable for
bundling into the ScramScreen iOS app.

Usage:
    python3 fetch_speed_cameras.py [output_path]

Default output: speed_cameras.sqlite in the current directory.
"""

import json
import sqlite3
import sys
import urllib.request

OVERPASS_URL = "https://overpass-api.de/api/interpreter"

OVERPASS_QUERY = """\
[out:json][timeout:120];
node["highway"="speed_camera"](45.5,5.5,48.2,10.8);
out body;
"""

# Map OSM enforcement type tags to our CameraType enum values.
_TYPE_MAP = {
    "speed_camera": "fixed",
    "maxspeed": "fixed",
    "average_speed": "section",
    "traffic_signals": "redLight",
    "red_light": "redLight",
    "mobile": "mobile",
}


def fetch_overpass() -> list[dict]:
    """Query Overpass API and return the list of OSM elements."""
    data = urllib.parse.urlencode({"data": OVERPASS_QUERY}).encode()
    req = urllib.request.Request(OVERPASS_URL, data=data, method="POST")
    req.add_header("User-Agent", "ScramScreen/fetch-speed-cameras (https://github.com/moto2000)")
    with urllib.request.urlopen(req, timeout=90) as resp:
        body = json.loads(resp.read())
    return body.get("elements", [])


def parse_camera(element: dict) -> dict:
    """Extract camera fields from an OSM node element."""
    tags = element.get("tags", {})

    # Speed limit
    speed_limit = None
    raw = tags.get("maxspeed", "")
    try:
        speed_limit = int(raw)
    except (ValueError, TypeError):
        pass

    # Camera type
    enforcement = tags.get("enforcement", "").lower()
    camera_type = _TYPE_MAP.get(enforcement, "unknown")

    return {
        "lat": element["lat"],
        "lon": element["lon"],
        "speed_limit": speed_limit,
        "type": camera_type,
    }


def write_sqlite(cameras: list[dict], path: str) -> None:
    """Write camera records to a SQLite database at *path*."""
    conn = sqlite3.connect(path)
    conn.execute("DROP TABLE IF EXISTS cameras")
    conn.execute(
        """
        CREATE TABLE cameras (
            id          INTEGER PRIMARY KEY,
            lat         REAL    NOT NULL,
            lon         REAL    NOT NULL,
            speed_limit INTEGER,
            type        TEXT    NOT NULL DEFAULT 'unknown'
        )
        """
    )
    conn.executemany(
        "INSERT INTO cameras (lat, lon, speed_limit, type) VALUES (?, ?, ?, ?)",
        [(c["lat"], c["lon"], c["speed_limit"], c["type"]) for c in cameras],
    )
    conn.commit()
    conn.close()


def main() -> None:
    output = sys.argv[1] if len(sys.argv) > 1 else "speed_cameras.sqlite"

    print("Querying Overpass API for Swiss speed cameras...")
    elements = fetch_overpass()
    print(f"  received {len(elements)} OSM elements")

    cameras = [parse_camera(e) for e in elements if e.get("type") == "node"]
    print(f"  parsed {len(cameras)} cameras")

    write_sqlite(cameras, output)
    print(f"  wrote {output}")


if __name__ == "__main__":
    main()
