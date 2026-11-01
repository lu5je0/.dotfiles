/* SPDX-License-Identifier: GPL-2.0 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <libevdev/libevdev.h>
#include <libevdev/libevdev-uinput.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/signalfd.h>
#include <sys/timerfd.h>
#include <systemd/sd-daemon.h>
#include <time.h>
#include <unistd.h>
#include "state.h"

static struct libevdev_uinput *output;
static bool dirty;
static unsigned long reads, frames;
static double read_seconds, max_read_seconds;

static double now(clockid_t clock)
{
    struct timespec ts;
    if (clock_gettime(clock, &ts)) {
        perror("clock_gettime");
        exit(EXIT_FAILURE);
    }
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int write_event(void *ctx, unsigned int type, unsigned int code, int value)
{
    (void)ctx;
    int ret = libevdev_uinput_write_event(output, type, code, value);
    if (!ret)
        dirty = true;
    else
        errno = -ret;
    return ret;
}

static int sync_output(void)
{
    if (!dirty)
        return 0;
    dirty = false;
    int ret = libevdev_uinput_write_event(output, EV_SYN, SYN_REPORT, 0);
    if (ret)
        errno = -ret;
    return ret;
}

static int refresh(int ec, struct bridge_state *state)
{
    char buf[4];
    double start = now(CLOCK_MONOTONIC);
    ssize_t n = pread(ec, buf, sizeof(buf) - 1, 0);
    double elapsed = now(CLOCK_MONOTONIC) - start;
    reads++;
    read_seconds += elapsed;
    if (elapsed > max_read_seconds)
        max_read_seconds = elapsed;
    if (n != 3 || buf[2] != '\n') {
        if (n >= 0)
            errno = EPROTO;
        return -1;
    }
    buf[n] = 0;
    char *end;
    unsigned long modifiers = strtoul(buf, &end, 16);
    if (end != buf + 2 || modifiers > 255) {
        errno = EPROTO;
        return -1;
    }
    return set_modifiers(state, modifiers, write_event, NULL);
}

static int arm_timer(int timer, unsigned int ms)
{
    /* 一次性 timer；每次实际检查后重设，键盘事件不会叠加积压的定时读取。 */
    struct itimerspec spec = { .it_value = { ms / 1000, (ms % 1000) * 1000000 } };
    return timerfd_settime(timer, 0, &spec, NULL);
}

static int open_keyboard(struct libevdev **device)
{
    glob_t paths = {0};
    int fd = -1;
    if (glob("/dev/input/event*", 0, NULL, &paths))
        return -1;
    for (size_t i = 0; i < paths.gl_pathc; i++) {
        int candidate = open(paths.gl_pathv[i], O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        struct libevdev *dev = NULL;
        if (candidate < 0)
            continue;
        if (libevdev_new_from_fd(candidate, &dev) == 0 &&
            libevdev_get_id_bustype(dev) == BUS_I8042 &&
            libevdev_get_id_vendor(dev) == 1 && libevdev_get_id_product(dev) == 1 &&
            strcmp(libevdev_get_name(dev), "AT Translated Set 2 keyboard") == 0) {
            *device = dev;
            fd = candidate;
            break;
        }
        libevdev_free(dev);
        close(candidate);
    }
    globfree(&paths);
    if (fd < 0)
        errno = ENODEV;
    return fd;
}

static unsigned int interval(const char *text)
{
    char *end;
    unsigned long value = strtoul(text, &end, 10);
    if (!*text || *end || value < 5 || value > 1000) {
        fprintf(stderr, "interval must be 5..1000 ms\n");
        exit(EXIT_FAILURE);
    }
    return value;
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: fn-ctrl IDLE_MS HELD_MS\n");
        return EXIT_FAILURE;
    }
    unsigned int idle_ms = interval(argv[1]), held_ms = interval(argv[2]);
    if (held_ms > idle_ms)
        return EXIT_FAILURE;
    int ret = EXIT_FAILURE, source = -1, ec = -1, timer = -1, signals = -1;
    int lock = -1;
    struct libevdev *device = NULL;
    struct bridge_state state = {0};
    double start = now(CLOCK_MONOTONIC), cpu_start = now(CLOCK_PROCESS_CPUTIME_ID);
    double suspend_offset = now(CLOCK_BOOTTIME) - now(CLOCK_MONOTONIC);
    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGINT);
    sigaddset(&mask, SIGTERM);
    if (sigprocmask(SIG_BLOCK, &mask, NULL))
        goto cleanup;
    signals = signalfd(-1, &mask, SFD_CLOEXEC | SFD_NONBLOCK);
    lock = open("/run/fn-ctrl/lock", O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (signals < 0 || lock < 0 || flock(lock, LOCK_EX | LOCK_NB))
        goto cleanup;
    ec = open("/sys/kernel/fn_ctrl_ec/modifiers", O_RDONLY | O_CLOEXEC);
    if (ec < 0)
        goto cleanup;
    /* 检查 EC 后才接管键盘；尚无输出设备，只验证读取是否成功。 */
    char initial[4];
    if (pread(ec, initial, sizeof(initial), 0) != 3)
        goto cleanup;
    source = open_keyboard(&device);
    if (source < 0)
        goto cleanup;
    int status = libevdev_grab(device, LIBEVDEV_GRAB);
    if (status) {
        errno = -status;
        goto cleanup;
    }
    /* keyd 只处理这个替代设备；原始 0001:0001 在配置中排除。 */
    libevdev_set_name(device, "Fn EC keyboard bridge");
    libevdev_set_id_bustype(device, BUS_VIRTUAL);
    libevdev_set_id_vendor(device, 0x1209);
    libevdev_set_id_product(device, 0xf1c0);
    libevdev_disable_event_type(device, EV_MSC);
    libevdev_disable_event_type(device, EV_LED);
    libevdev_disable_event_type(device, EV_REP);
    status = libevdev_uinput_create_from_device(device, LIBEVDEV_UINPUT_OPEN_MANAGED, &output);
    if (status) {
        errno = -status;
        goto cleanup;
    }
    timer = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC | TFD_NONBLOCK);
    if (timer < 0 || refresh(ec, &state) < 0 || sync_output() < 0 || arm_timer(timer, idle_ms))
        goto cleanup;
    sd_notify(0, "READY=1\nSTATUS=Bridging internal keyboard to keyd");
    fprintf(stderr, "Fn/Ctrl bridge ready; idle=%ums held=%ums\n", idle_ms, held_ms);
    double last_notify = now(CLOCK_MONOTONIC);
    for (;;) {
        struct pollfd fds[] = {
            { source, POLLIN, 0 }, { timer, POLLIN, 0 }, { signals, POLLIN, 0 }
        };
        int ready = poll(fds, 3, -1);
        if (ready < 0) {
            if (errno == EINTR)
                continue;
            goto cleanup;
        }
        if (fds[2].revents & POLLIN) {
            ret = EXIT_SUCCESS;
            break;
        }
        if ((fds[0].revents | fds[1].revents) & (POLLERR | POLLHUP | POLLNVAL))
            goto cleanup;
        double offset = now(CLOCK_BOOTTIME) - now(CLOCK_MONOTONIC);
        if (offset - suspend_offset > 0.1) {
            /* 休眠期间不轮询；恢复后先释放旧状态，再按新 EC 状态同步。 */
            if (release_keys(&state, write_event, NULL) < 0 || sync_output() < 0)
                goto cleanup;
            suspend_offset = offset;
        }
        if (fds[1].revents & POLLIN) {
            uint64_t expirations;
            if (read(timer, &expirations, sizeof(expirations)) != sizeof(expirations))
                goto cleanup;
        }
        /* 有物理事件时先读 EC，保证 Ctrl 先于字母输出；无需等空闲定时器。 */
        if (refresh(ec, &state) < 0)
            goto cleanup;
        if (fds[0].revents & POLLIN) {
            struct input_event event;
            int status;
            while ((status = libevdev_next_event(device, LIBEVDEV_READ_FLAG_NORMAL, &event)) == 0) {
                if (event.type == EV_KEY && forward_key(&state, event.code, event.value,
                                                        write_event, NULL) < 0)
                    goto cleanup;
                if (event.type == EV_SYN && event.code == SYN_REPORT) {
                    frames++;
                    if (sync_output() < 0)
                        goto cleanup;
                }
            }
            /* SYN_DROPPED 或拔出时释放全部虚拟键并交给 systemd 重建，避免卡键。 */
            if (status != -EAGAIN) {
                errno = status < 0 ? -status : EOVERFLOW;
                goto cleanup;
            }
        }
        if (sync_output() < 0 || arm_timer(timer, state.fn ? held_ms : idle_ms))
            goto cleanup;
        double current = now(CLOCK_MONOTONIC);
        if (current - last_notify >= 10) {
            sd_notify(0, "WATCHDOG=1");
            last_notify = current;
        }
    }
cleanup:
    if (ret)
        fprintf(stderr, "bridge stopped on input/EC error: %s\n", strerror(errno));
    sd_notify(0, "STOPPING=1");
    if (output) {
        release_keys(&state, write_event, NULL);
        sync_output();
        libevdev_uinput_destroy(output);
    }
    libevdev_free(device);
    if (source >= 0) close(source);
    if (ec >= 0) close(ec);
    if (timer >= 0) close(timer);
    if (signals >= 0) close(signals);
    if (lock >= 0) close(lock);
    double elapsed = now(CLOCK_MONOTONIC) - start;
    fprintf(stderr, "runtime=%.1fs reads=%lu frames=%lu EC_wait=%.3fs max_read=%.2fms CPU=%.3fs\n",
            elapsed, reads, frames, read_seconds, max_read_seconds * 1000,
            now(CLOCK_PROCESS_CPUTIME_ID) - cpu_start);
    return ret;
}
