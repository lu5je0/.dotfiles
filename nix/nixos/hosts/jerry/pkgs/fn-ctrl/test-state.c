/* SPDX-License-Identifier: GPL-2.0 */
#include <assert.h>
#include <stdio.h>
#include "state.h"

struct event { unsigned int type, code; int value; };
static struct event events[64];
static size_t count;

static int capture(void *ctx, unsigned int type, unsigned int code, int value)
{
    (void)ctx;
    assert(count < sizeof(events) / sizeof(events[0]));
    events[count++] = (struct event){ type, code, value };
    return 0;
}

static void expect(size_t index, unsigned int code, int value)
{
    assert(index < count);
    assert(events[index].type == EV_KEY);
    assert(events[index].code == code);
    assert(events[index].value == value);
}

int main(void)
{
    struct bridge_state state = {0};
    assert(set_modifiers(&state, 0x40, capture, NULL) == 0);
    forward_key(&state, KEY_LEFTMETA, 1, capture, NULL);
    /* Fn+I 的 Insert 按下、重复、松开均还原；Fn 先松开也要释放 I。 */
    forward_key(&state, KEY_INSERT, 1, capture, NULL);
    forward_key(&state, KEY_INSERT, 2, capture, NULL);
    set_modifiers(&state, 0x00, capture, NULL);
    forward_key(&state, KEY_INSERT, 0, capture, NULL);
    expect(0, KEY_LEFTCTRL, 1);
    expect(1, KEY_LEFTMETA, 1);
    expect(2, KEY_I, 1);
    expect(3, KEY_I, 2);
    expect(4, KEY_LEFTCTRL, 0);
    expect(5, KEY_I, 0);

    /* 普通 Insert 不改写；先按 Insert 后按 Fn，松开仍对应 Insert。 */
    forward_key(&state, KEY_INSERT, 1, capture, NULL);
    set_modifiers(&state, 0x40, capture, NULL);
    forward_key(&state, KEY_INSERT, 0, capture, NULL);
    expect(6, KEY_INSERT, 1);
    expect(8, KEY_INSERT, 0);

    /* 固件合成的 Ctrl 点击不能释放 Fn；真实左 Ctrl 与 Fn 重叠不重复触发。 */
    size_t before = count;
    forward_key(&state, KEY_LEFTCTRL, 1, capture, NULL);
    forward_key(&state, KEY_LEFTCTRL, 0, capture, NULL);
    set_modifiers(&state, 0x50, capture, NULL);
    set_modifiers(&state, 0x10, capture, NULL);
    assert(count == before);
    set_modifiers(&state, 0x00, capture, NULL);
    expect(before, KEY_LEFTCTRL, 0);

    /* Shift/右 Ctrl 原样转发，退出和恢复清空所有按键及映射。 */
    set_modifiers(&state, 0x40, capture, NULL);
    forward_key(&state, KEY_LEFTSHIFT, 1, capture, NULL);
    forward_key(&state, KEY_RIGHTCTRL, 1, capture, NULL);
    forward_key(&state, KEY_INSERT, 1, capture, NULL);
    before = count;
    assert(release_keys(&state, capture, NULL) == 0);
    assert(count == before + 5); /* I、Shift、右 Ctrl、Win、左 Ctrl */
    before = count;
    release_keys(&state, capture, NULL);
    assert(count == before);
    assert(!state.fn && !state.ctrl);
    for (unsigned int i = 0; i < KEY_CNT; i++)
        assert(!state.down[i] && !state.mapped[i]);
    assert(forward_key(&state, KEY_CNT, 1, capture, NULL) < 0);
    /* Fn+B 的 Pause 脉冲还原为 Ctrl+B，之后输入 % 时 Ctrl 已释放。 */
    count = 0;
    set_modifiers(&state, 0x40, capture, NULL);
    forward_key(&state, KEY_PAUSE, 1, capture, NULL);
    forward_key(&state, KEY_PAUSE, 0, capture, NULL);
    set_modifiers(&state, 0x00, capture, NULL);
    forward_key(&state, KEY_LEFTSHIFT, 1, capture, NULL);
    forward_key(&state, KEY_5, 1, capture, NULL);
    forward_key(&state, KEY_5, 0, capture, NULL);
    forward_key(&state, KEY_LEFTSHIFT, 0, capture, NULL);
    expect(0, KEY_LEFTCTRL, 1);
    expect(1, KEY_B, 1);
    expect(2, KEY_B, 0);
    expect(3, KEY_LEFTCTRL, 0);
    expect(4, KEY_LEFTSHIFT, 1);
    expect(5, KEY_5, 1);
    expect(6, KEY_5, 0);
    expect(7, KEY_LEFTSHIFT, 0);

    /* Fn 先松开仍释放 B；普通 Pause 及先按 Pause 后按 Fn 不改写。 */
    count = 0;
    set_modifiers(&state, 0x40, capture, NULL);
    forward_key(&state, KEY_PAUSE, 1, capture, NULL);
    set_modifiers(&state, 0x00, capture, NULL);
    forward_key(&state, KEY_PAUSE, 0, capture, NULL);
    expect(3, KEY_B, 0);
    forward_key(&state, KEY_PAUSE, 1, capture, NULL);
    set_modifiers(&state, 0x40, capture, NULL);
    forward_key(&state, KEY_PAUSE, 0, capture, NULL);
    expect(4, KEY_PAUSE, 1);
    expect(6, KEY_PAUSE, 0);
    release_keys(&state, capture, NULL);
    puts("Fn/Ctrl ordering, modifier overlap, Insert/Pause pairing, prefix and cleanup passed");
    return 0;
}
