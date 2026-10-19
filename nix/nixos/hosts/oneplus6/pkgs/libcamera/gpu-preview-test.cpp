#include <array>
#include <cassert>
#include <cmath>
#include "libcamera/internal/software_isp/quad_bayer.h"

using namespace libcamera;
int main()
{
    // All three sensor sizes, common output ratios and a small preview.
    for (Size input : {Size(4656,3496), Size(4656,3456), Size(2592,1940)}) {
        for (Size output : {Size(1920,1080), Size(1280,720), Size(640,480), Size(320,240), Size(720,1280)}) {
            Rectangle crop = quadBayerStatsWindow(input, output);
            assert(crop.x >= 0 && crop.y >= 0 && crop.width > 0 && crop.height > 0);
            assert(crop.x % 4 == 0 && crop.y % 4 == 0 && crop.width % 4 == 0 && crop.height % 4 == 0);
            assert(crop.x + crop.width <= input.width && crop.y + crop.height <= input.height);
            assert(std::abs(int(input.width - crop.width) - 2 * crop.x) < 8);
            assert(std::abs(int(input.height - crop.height) - 2 * crop.y) < 8);
            assert(std::abs(double(crop.width) / crop.height - double(output.width) / output.height) < .01);
            auto coords = softwareIspTextureCoordinates(input, crop, true);
            // The texture rectangle and statistics select precisely the same RAW pixels.
            assert(std::abs(coords[0] * input.width - crop.x) < .001);
            assert(std::abs(coords[1] * input.height - crop.y) < .001);
            assert(std::abs(coords[4] * input.width - crop.x - crop.width) < .001);
            assert(std::abs(coords[5] * input.height - crop.y - crop.height) < .001);
            auto viewport = softwareIspViewport(input, output, true);
            assert(viewport.x == 0 && viewport.y == 0 && viewport.width == output.width && viewport.height == output.height);
        }
    }
    auto main = quadBayerStatsWindow({4656,3496}, {1920,1080});
    assert(main.x == 0 && main.y == 440 && main.width == 4656 && main.height == 2616);
}
