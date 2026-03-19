#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../bridge-status.h"
#include "../clipboard-bridge.h"

static void normalize_lf_inplace(char *text) {
    if (!text) return;
    char *src = text;
    char *dst = text;
    while (*src) {
        if (src[0] == '\r' && src[1] == '\n') {
            *dst++ = '\n';
            src += 2;
            continue;
        }
        *dst++ = *src++;
    }
    *dst = '\0';
}

int bridge_clipboard_output(const char *eol, char **text_out) {
    if (!text_out) {
        return BRIDGE_STATUS_INVALID_PARAMS;
    }
    *text_out = NULL;

    if (eol && strcmp(eol, "lf") != 0) {
        return BRIDGE_STATUS_INVALID_PARAMS;
    }

    FILE *fp = popen("pbpaste", "r");
    if (!fp) {
        return BRIDGE_STATUS_FAILED;
    }

    size_t capacity = 4096;
    size_t len = 0;
    char *buf = malloc(capacity);
    if (!buf) {
        pclose(fp);
        return BRIDGE_STATUS_FAILED;
    }

    size_t n;
    while ((n = fread(buf + len, 1, capacity - len - 1, fp)) > 0) {
        len += n;
        if (len + 1 >= capacity) {
            capacity *= 2;
            char *newbuf = realloc(buf, capacity);
            if (!newbuf) {
                free(buf);
                pclose(fp);
                return BRIDGE_STATUS_FAILED;
            }
            buf = newbuf;
        }
    }
    pclose(fp);

    buf[len] = '\0';
    normalize_lf_inplace(buf);
    *text_out = buf;
    return BRIDGE_STATUS_OK;
}

int bridge_clipboard_input(const char *text) {
    if (!text) {
        return BRIDGE_STATUS_INVALID_PARAMS;
    }

    FILE *fp = popen("pbcopy", "w");
    if (!fp) {
        return BRIDGE_STATUS_FAILED;
    }

    size_t len = strlen(text);
    if (fwrite(text, 1, len, fp) != len) {
        pclose(fp);
        return BRIDGE_STATUS_FAILED;
    }

    pclose(fp);
    return BRIDGE_STATUS_OK;
}
