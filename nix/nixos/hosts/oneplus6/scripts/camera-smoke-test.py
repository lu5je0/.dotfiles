#!/usr/bin/env python3
"""Capture processed frames from each OnePlus 6 camera with the real ISP."""
import argparse
import datetime
import json
import pathlib
import subprocess
import time

CAMERAS = {
    "main": "/base/soc@0/cci@ac4a000/i2c-bus@0/camera@1a",
    "secondary": "/base/soc@0/cci@ac4a000/i2c-bus@1/camera@10",
    "front": "/base/soc@0/cci@ac4a000/i2c-bus@0/camera@10",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cam", default="cam")
    parser.add_argument("--directory", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.directory.mkdir(mode=0o700, parents=True, exist_ok=False)
    results = []
    for name, camera_id in CAMERAS.items():
        image = args.directory / (name + ".ppm")
        command = [
            args.cam,
            "--camera=" + camera_id,
            "--capture=30",
            "--stream=role=viewfinder,width=640,height=480,pixelformat=ABGR8888",
            "--file=" + str(image),
        ]
        started = time.monotonic()
        try:
            completed = subprocess.run(
                command, capture_output=True, text=True, timeout=25
            )
            status = completed.returncode
            output = completed.stdout + completed.stderr
        except subprocess.TimeoutExpired as error:
            status = "timeout"
            output = (error.stdout or b"").decode(errors="replace")
            output += (error.stderr or b"").decode(errors="replace")
        (args.directory / (name + ".log")).write_text(output)
        result = {
            "camera": name,
            "id": camera_id,
            "exit": status,
            "duration_seconds": round(time.monotonic() - started, 3),
            "file": str(image),
            "passed": False,
        }
        if image.exists():
            try:
                with image.open("rb") as stream:
                    magic = stream.readline().strip()
                    width, height = map(int, stream.readline().split())
                    maximum = stream.readline().strip()
                    pixels = stream.read()
                result.update(
                    width=width,
                    height=height,
                    pixel_bytes=len(pixels),
                    min_value=min(pixels, default=0),
                    max_value=max(pixels, default=0),
                    passed=(
                        status == 0
                        and magic == b"P6"
                        and maximum == b"255"
                        and len(pixels) == width * height * 3
                    ),
                )
            except (OSError, ValueError) as error:
                result["image_error"] = str(error)
        results.append(result)
        print(json.dumps(result), flush=True)
    report = {
        "recorded_at": datetime.datetime.now().astimezone().isoformat(),
        "frames_per_camera": 30,
        "results": results,
        "passed": all(result["passed"] for result in results),
    }
    (args.directory / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
