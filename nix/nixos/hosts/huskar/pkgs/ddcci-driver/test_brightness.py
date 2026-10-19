"""Fault-inject the actual upstream/patched update_status C function.

Usage: python3 test_brightness.py /path/to/patched/ddcci-backlight.c
"""

import pathlib
import subprocess
import sys
import tempfile


HARNESS = r"""
#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#define FB_BLANK_UNBLANK 0
#define BL_CORE_FBBLANK 1
struct ddcci_device { int unused; };
struct ddcci_monitor_drv_data {
    struct ddcci_device *device;
    unsigned char used_vcp;
};
struct backlight_device {
    struct { int brightness, power, state; } props;
    struct ddcci_monitor_drv_data *data;
};
#define bl_get_data(bl) ((bl)->data)

static int hardware = 30, writes, reads, sleeps;
static int ignored_writes, failed_writes, failed_reads;
static int last_target;
static int ddcci_monitor_writectrl(struct ddcci_device *dev,
                                  unsigned char vcp, unsigned short value)
{
    (void)dev; (void)vcp;
    writes++;
    last_target = value;
    if (writes <= failed_writes)
        return -ENXIO;
    if (writes > ignored_writes)
        hardware = value;
    return 4;
}
static int ddcci_monitor_readctrl(struct ddcci_device *dev,
                                 unsigned char vcp, unsigned short *value,
                                 unsigned short *maximum)
{
    (void)dev; (void)vcp; (void)maximum;
    reads++;
    if (reads <= failed_reads)
        return -EIO;
    *value = hardware;
    return 0;
}
static void msleep(unsigned int delay) { assert(delay == 100); sleeps++; }

FUNCTION

int main(int argc, char **argv)
{
    assert(argc == 2);
    int scenario = atoi(argv[1]);
    struct ddcci_monitor_drv_data data = {0};
    struct backlight_device bl = {.props = {89, 0, 0}, .data = &data};
    switch (scenario) {
    case 0: ignored_writes = 3; break;
    case 1: failed_writes = 2; break;
    case 2: failed_reads = 2; break;
    case 3: ignored_writes = 100; break;
    case 4: failed_writes = 100; break;
    case 5: failed_reads = 100; break;
    case 6: bl.props.power = 4; break;
    case 7: bl.props.state = BL_CORE_FBBLANK; break;
    case 8: break;
    default: abort();
    }
    int result = ddcci_backlight_update_status(&bl);
    printf("%d %d %d %d %d %d %d\n", result, hardware, writes, reads,
           sleeps, last_target, bl.props.brightness);
}
"""


def extract(source):
    start = source.index("static int ddcci_backlight_update_status(")
    end = source.index("\nstatic int ddcci_backlight_get_brightness(", start)
    return source[start:end]


def main():
    source_path = pathlib.Path(sys.argv[1]).resolve()
    patched = source_path.read_text()
    # Keep the pre-fix behavior as a negative control; execute the actual
    # patched C function for all regression scenarios below.
    original = r"""
static int ddcci_backlight_update_status(struct backlight_device *bl)
{
    struct ddcci_monitor_drv_data *drv_data = bl_get_data(bl);
    int brightness = bl->props.brightness;
    int ret;
    if (bl->props.power != FB_BLANK_UNBLANK ||
        bl->props.state & BL_CORE_FBBLANK)
        brightness = 0;
    ret = ddcci_monitor_writectrl(drv_data->device, drv_data->used_vcp,
                                 brightness);
    if (ret > 0)
        ret = 0;
    return ret;
}
"""
    with tempfile.TemporaryDirectory() as directory:
        binaries = {}
        for name, source in (("original", original), ("patched", patched)):
            path = pathlib.Path(directory, name + ".c")
            function = extract(source) if name == "patched" else source
            path.write_text(HARNESS.replace("FUNCTION", function))
            binary = path.with_suffix("")
            subprocess.run(
                ["cc", "-std=c11", "-Wall", "-Wextra", "-Werror",
                 "-Wno-unused-function", str(path), "-o", str(binary)],
                check=True,
            )
            binaries[name] = binary

        def run(name, scenario):
            return tuple(map(int, subprocess.check_output(
                [str(binaries[name]), str(scenario)], text=True
            ).split()))

        # Before the patch, an acknowledged but ignored restore reports success.
        assert run("original", 0)[:3] == (0, 30, 1)
        expected = {
            0: (0, 89, 4, 4, 3, 89, 89),  # ACKs before brightness is ready
            1: (0, 89, 3, 1, 2, 89, 89),  # transport unavailable during wake
            2: (0, 89, 3, 3, 2, 89, 89),  # transient readback failures
            3: (-5, 30, 20, 20, 19, 89, 89),  # never applies: bounded EIO
            4: (-6, 30, 20, 0, 19, 89, 89),  # disconnected: preserve ENXIO
            5: (-5, 89, 20, 20, 19, 89, 89),  # cannot verify: no false success
            6: (0, 0, 1, 1, 0, 0, 89),  # power blank keeps requested level
            7: (0, 0, 1, 1, 0, 0, 89),  # framebuffer blank
            8: (0, 89, 1, 1, 0, 89, 89),  # normal write: no retry/delay
        }
        for scenario, result in expected.items():
            actual = run("patched", scenario)
            assert actual == result, (scenario, actual, result)
        print("PASS: original false success reproduced; 9 patched scenarios passed")


if __name__ == "__main__":
    main()
