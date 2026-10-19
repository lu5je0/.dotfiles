/* SPDX-License-Identifier: LGPL-2.1-or-later */
#undef NDEBUG
#include <cassert>
#include <initializer_list>
#include "imx376_pdaf.h"

int main()
{
 using namespace libcamera;
 /* Measured 16x16 tile: eight high-valued blue phase-detection pixels. */
 const unsigned int rows[16] = {
  0, 0x0202, 0, 0, 0, 0x2020, 0, 0,
  0, 0x2020, 0, 0, 0, 0x0202, 0, 0
 };
 assert(imx376PdafPixel(1, 1, 2592, 1940, false, false));
 assert(imx376PdafPixel(2590, 1938, 2592, 1940, true, true));
 assert(!imx376PdafPixel(3, 1, 2592, 1940, false, false));
 assert(!imx376PdafPixel(1, 1, 4656, 3496, false, false));
 for (bool h : { false, true }) for (bool v : { false, true }) {
  auto read = [&](unsigned int x, unsigned int y) -> unsigned int {
   assert(x < 2592 && y < 1940);
   unsigned int nx = h ? 2591 - x : x;
   unsigned int ny = v ? 1939 - y : y;
   return (rows[ny % 16] & (1U << (nx % 16))) ? 200 : 40;
  };
  for (unsigned int y = 0; y < 1940; y++)
   for (unsigned int x = 0; x < 2592; x++)
    assert(imx376CorrectedPixel(x, y, 2592, 1940, h, v, read) == 40);
 }
}
