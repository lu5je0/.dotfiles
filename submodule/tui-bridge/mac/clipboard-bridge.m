#import <AppKit/AppKit.h>
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

    @autoreleasepool {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        NSString *str = [pb stringForType:NSPasteboardTypeString];
        if (!str) {
            char *empty = malloc(1);
            if (!empty) {
                return BRIDGE_STATUS_FAILED;
            }
            empty[0] = '\0';
            *text_out = empty;
            return BRIDGE_STATUS_OK;
        }

        const char *utf8 = [str UTF8String];
        if (!utf8) {
            return BRIDGE_STATUS_FAILED;
        }
        size_t len = strlen(utf8);
        char *buf = malloc(len + 1);
        if (!buf) {
            return BRIDGE_STATUS_FAILED;
        }
        memcpy(buf, utf8, len + 1);
        normalize_lf_inplace(buf);
        *text_out = buf;
        return BRIDGE_STATUS_OK;
    }
}

int bridge_clipboard_input(const char *text) {
    if (!text) {
        return BRIDGE_STATUS_INVALID_PARAMS;
    }

    @autoreleasepool {
        NSString *str = [[NSString alloc] initWithUTF8String:text];
        if (!str) {
            return BRIDGE_STATUS_FAILED;
        }
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        BOOL ok = [pb setString:str forType:NSPasteboardTypeString];
        return ok ? BRIDGE_STATUS_OK : BRIDGE_STATUS_FAILED;
    }
}
