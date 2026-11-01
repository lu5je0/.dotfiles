/* SPDX-License-Identifier: GPL-2.0 */
#pragma once
#include <linux/input.h>
#include <stdbool.h>
#include <string.h>

struct bridge_state {
    bool fn, ctrl;
    bool down[KEY_CNT];
    unsigned short mapped[KEY_CNT];
};

typedef int (*emit_fn)(void *, unsigned int, unsigned int, int);

static int set_modifiers(struct bridge_state *s, unsigned char modifiers,
                         emit_fn emit, void *ctx)
{
    bool ctrl = (modifiers & 0x50) != 0;
    s->fn = (modifiers & 0x40) != 0;
    if (ctrl == s->ctrl)
        return 0;
    if (emit(ctx, EV_KEY, KEY_LEFTCTRL, ctrl) < 0)
        return -1;
    s->ctrl = ctrl;
    return 0;
}

static int forward_key(struct bridge_state *s, unsigned int code, int value,
                       emit_fn emit, void *ctx)
{
    if (code >= KEY_CNT || value < 0 || value > 2)
        return -1;
    /* 固件的 Fool Proof Ctrl 点击由 EC 状态合并，不能独立转发松开事件。 */
    if (code == KEY_LEFTCTRL)
        return 0;
    if (value == 1 && !s->mapped[code])
        s->mapped[code] = s->fn && code == KEY_INSERT ? KEY_I : code;
    unsigned int target = s->mapped[code] ? s->mapped[code] : code;
    if (emit(ctx, EV_KEY, target, value) < 0)
        return -1;
    s->down[target] = value != 0;
    if (!value)
        s->mapped[code] = 0;
    return 0;
}

static int release_keys(struct bridge_state *s, emit_fn emit, void *ctx)
{
    int ret = 0;
    for (unsigned int key = 0; key < KEY_CNT; key++)
        if (s->down[key] && emit(ctx, EV_KEY, key, 0) < 0)
            ret = -1;
    if (s->ctrl && emit(ctx, EV_KEY, KEY_LEFTCTRL, 0) < 0)
        ret = -1;
    memset(s, 0, sizeof(*s));
    return ret;
}
