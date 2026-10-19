/* SPDX-License-Identifier: LGPL-2.1-or-later */
#include "exposure_stats.h"
#include <cassert>
#include <iostream>

using namespace libcamera;

int main()
{
    const std::array<float, 3> unity{1, 1, 1};
    ExposureStats stats;
    assert(stats.highlight(16, unity) == 0);
    for (int i = 0; i < 1000; ++i)
        stats.add(96, 128, 72);
    const double normal = stats.highlight(16, unity);
    assert(normal > 0.47 && normal < 0.49);
    assert(exposureCorrection(2.5, normal) == 1);
    /* A lamp occupying 1% must not suppress an otherwise normal scene. */
    for (int i = 0; i < 10; ++i)
        stats.add(255, 255, 255);
    assert(stats.highlight(16, unity) == normal);
    /* Broad clipped highlights override even a dark average meter. */
    ExposureStats broad;
    for (int i = 0; i < 100; ++i)
        broad.add(255, 255, 255);
    stats.merge(broad);
    assert(stats.highlight(16, unity) == 1);
    assert(exposureCorrection(1.5, stats.highlight(16, unity)) == 0.85);
    /* Red/blue white balance gain must be included before clipping. */
    ExposureStats coloured;
    for (int i = 0; i < 1000; ++i)
        coloured.add(96, 128, 120);
    assert(coloured.highlight(16, {2, 1, 2.5}) > 1.1);
    assert(exposureCorrection(2.5, coloured.highlight(16, {2, 1, 2.5})) < 1);
    assert(coloured.highlight(255, unity) == 0);
    assert(coloured.highlight(16, {NAN, 1, 1}) > 0);
    /* Low sample count and invalid control data never force a correction. */
    ExposureStats sparse;
    for (int i = 0; i < 63; ++i)
        sparse.add(255, 255, 255);
    assert(sparse.highlight(16, unity) == 0);
    assert(exposureCorrection(0, 1) == 1);
    assert(exposureCorrection(NAN, 1) == 1);
    assert(exposureCorrection(1, INFINITY) == 1);
    assert(exposureCorrection(1, -1) == 1);
    assert(exposureCorrection(1, 0.2) > 1); // dark scene can brighten
    assert(exposureCorrection(4, 0.5) < 1); // normal meter still works
    assert(exposureCorrection(1, 0.85) == 1); // no oscillation at limit
    assert(exposureCorrection(4, 0.85) < 1);
    assert(exposureCorrection(1, 0.5) <= 1.15);
    /* Exposure changes sensor signal above black, not black itself.
     * Start severely clipped; convergence recovers highlight detail without
     * bouncing back up under the average meter's constant brightening demand.
     */
    double exposure = 2;
    for (int frame = 0; frame < 100; ++frame) {
        ExposureStats scene;
        const unsigned int value = std::min(255.0, 16 + 200 * exposure);
        for (int i = 0; i < 1000; ++i)
            scene.add(value, value, value);
        exposure *= exposureCorrection(1.5, scene.highlight(16, unity));
    }
    assert(200 * exposure > 190 && 200 * exposure < 210);
    std::cout << "AGC highlight metering and convergence passed\n";
}
