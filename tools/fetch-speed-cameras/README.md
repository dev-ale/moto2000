# fetch-speed-cameras

Fetches Swiss speed camera data from OpenStreetMap via the Overpass API and
writes it to a SQLite database for bundling into the ScramScreen iOS app.

## Prerequisites

Python 3.10+ (standard library only, no extra packages).

## Usage

```bash
# Generate speed_cameras.sqlite in the current directory
python3 tools/fetch-speed-cameras/fetch_speed_cameras.py

# Or specify an output path
python3 tools/fetch-speed-cameras/fetch_speed_cameras.py path/to/output.sqlite
```

The script queries the Overpass API for `highway=speed_camera` nodes within
Switzerland (bounding box lat 45.8-47.9, lon 5.9-10.5) and writes a SQLite
file with a single `cameras` table:

| Column       | Type    | Description                        |
|--------------|---------|------------------------------------|
| id           | INTEGER | Auto-increment primary key         |
| lat          | REAL    | WGS-84 latitude                    |
| lon          | REAL    | WGS-84 longitude                   |
| speed_limit  | INTEGER | Speed limit in km/h (nullable)     |
| type         | TEXT    | Camera type: fixed, mobile, etc.   |

## Updating the bundled database

After running the script, copy the output file into the ScramCore resource
bundle:

```bash
cp speed_cameras.sqlite \
   app/ios/Packages/ScramCore/Sources/ScramCore/Resources/speed_cameras.sqlite
```

Then rebuild the app. The `BundledSpeedCameraDatabase` class will pick up the
updated file at launch.
