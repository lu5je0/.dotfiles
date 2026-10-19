#include <array>
#include <cassert>
#include <cmath>
#include "awb_stats.h"
using namespace libcamera;
int main()
{
    AwbAccumulator clean, contaminated, split;
    for (int i = 0; i < 1000; ++i) {
        clean.add(84, 134, 65);
        contaminated.add(84, 134, 65);
        split.add(84, 134, 65);
    }
    // Reproduce a bright OP6 scene: green clips before red and blue.
    for (int i = 0; i < 10000; ++i) {
        contaminated.add(200, 255, 140);
        contaminated.add(255, 200, 150);
        contaminated.add(120, 180, 255);
        contaminated.add(19, 21, 18);
    }
    assert(contaminated.count == clean.count);
    assert(contaminated.sum == clean.sum);
    std::array<float,3> a{}, b{};
    assert(clean.gains(16, a) && contaminated.gains(16, b));
    assert(a == b);
    assert(std::abs(a[0] - 118.0f/68) < 1e-5);
    assert(std::abs(a[2] - 118.0f/49) < 1e-5);
    clean.merge(split);
    assert(clean.count == 2000 && clean.gains(16, b) && a == b);
    AwbAccumulator empty;
    b = {2,1,3};
    assert(!empty.gains(16,b) && b[0] == 2 && b[2] == 3);
    for (int i=0;i<63;++i) empty.add(30,200,40);
    assert(!empty.gains(16,b));
    empty.add(30,200,40);
    assert(empty.gains(16,b) && b[0] == 4 && b[2] == 4);
    assert(!empty.gains(220,b));
    AwbAccumulator boundary;
    boundary.add(24,100,100); boundary.add(100,240,100);
    boundary.add(25,239,25);
    assert(boundary.count == 1);
    // A large image/merged jobs must not overflow 32-bit channel sums.
    AwbAccumulator large;
    large.count = uint64_t(1) << 32;
    large.sum = {large.count*84,large.count*134,large.count*65};
    assert(large.gains(16,b) && a == b);
}
