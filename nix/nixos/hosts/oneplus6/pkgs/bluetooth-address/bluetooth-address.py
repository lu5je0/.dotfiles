"""Supply a stable address when the WCN3990 reports missing public-address."""
import argparse
import hashlib
import pathlib
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--btmgmt", required=True)
    args = parser.parse_args()
    identity = pathlib.Path("/etc/machine-id").read_text().strip()
    if not identity:
        raise SystemExit("A nonempty machine-id is required for a stable address")
    digest = hashlib.sha256(("oneplus6-bluetooth:" + identity).encode()).digest()
    address = "02:" + ":".join(f"{byte:02X}" for byte in digest[:5])
    deadline = time.monotonic() + 30
    last_error = "WCN3990 controller not ready"
    while time.monotonic() < deadline:
        for controller in pathlib.Path("/sys/class/bluetooth").glob("hci*"):
            compatible = controller / "device/of_node/compatible"
            try:
                if b"qcom,wcn3990-bt" not in compatible.read_bytes().split(b"\0"):
                    continue
                command = [args.btmgmt, "-i", controller.name[3:]]
                result = subprocess.run(
                    command + ["config"], capture_output=True, text=True, timeout=5
                )
                missing = next(
                    (line for line in result.stdout.splitlines() if "missing options:" in line),
                    None,
                )
                if missing is None:
                    last_error = result.stdout.strip() or result.stderr.strip()
                    continue
                if "public-address" not in missing:
                    print(f"{controller.name}: public address is configured", flush=True)
                    return
                result = subprocess.run(
                    command + ["public-addr", address],
                    capture_output=True, text=True, timeout=5,
                )
                # btmgmt can exit with zero even when the management command
                # fails. Wait for Read Configuration to confirm success.
                last_error = result.stdout.strip() or result.stderr.strip()
                print(f"{controller.name}: configuring stable address {address}: {last_error}", flush=True)
            except (OSError, subprocess.TimeoutExpired) as error:
                last_error = str(error)
        time.sleep(1)
    raise SystemExit(f"Bluetooth address setup timed out: {last_error}")


if __name__ == "__main__":
    main()
