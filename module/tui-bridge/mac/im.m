#import <Carbon/Carbon.h>
#import <AppKit/AppKit.h>
#include <stdbool.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

#include "../im.h"

static NSString *asciiSourceID = nil;
static NSString *savedSourceID = nil;
static NSString *lastReportedSourceID = nil;
static BOOL initialized = NO;
static BOOL watchEnabled = NO;

static NSString *getInputSourceID(TISInputSourceRef source) {
    if (!source) return nil;
    CFStringRef sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    return (__bridge NSString *)sourceID;
}

static NSString *getCurrentInputSourceID(void) {
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (!source) return nil;
    NSString *sourceID = getInputSourceID(source);
    CFRelease(source);
    return sourceID;
}

static NSString *getASCIIInputSourceID(void) {
    TISInputSourceRef source = TISCopyCurrentASCIICapableKeyboardInputSource();
    if (!source) return nil;
    NSString *sourceID = getInputSourceID(source);
    CFRelease(source);
    return sourceID;
}

static BOOL selectInputSource(NSString *sourceID) {
    if (!sourceID) return NO;
    NSDictionary *filter = @{(__bridge NSString *)kTISPropertyInputSourceID: sourceID};
    CFArrayRef sources = TISCreateInputSourceList((__bridge CFDictionaryRef)filter, false);
    if (!sources || CFArrayGetCount(sources) == 0) {
        if (sources) CFRelease(sources);
        return NO;
    }
    TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, 0);
    OSStatus status = TISSelectInputSource(source);
    CFRelease(sources);
    return status == noErr;
}

static void inputSourceChanged(CFNotificationCenterRef center,
                               void *observer,
                               CFNotificationName name,
                               const void *object,
                               CFDictionaryRef userInfo) {
    NSString *currentID = getCurrentInputSourceID();
    if (!currentID) return;

    BOOL changed = ![currentID isEqualToString:lastReportedSourceID];
    // Always track the latest source so dedup state stays in sync even while
    // watch is disabled (e.g. during insert mode, where im_insert/im_normal
    // programmatically switch the TIS source). Otherwise re-enabling watch
    // could leave lastReportedSourceID stale and suppress the next real change.
    lastReportedSourceID = currentID;

    if (!watchEnabled || !changed) return;

    const char *state = (asciiSourceID && [currentID isEqualToString:asciiSourceID]) ? "ascii" : "ime";
    bridge_emit_ime_changed_full([currentID UTF8String], state);
}

static void setup(void) {
    if (initialized) return;
    initialized = YES;
    
    asciiSourceID = getASCIIInputSourceID();
    
    // Monitor input source changes
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDistributedCenter(),
        NULL,
        inputSourceChanged,
        kTISNotifySelectedKeyboardInputSourceChanged,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

const char *im_normal(void) {
    @autoreleasepool {
        setup();
        
        NSString *currentID = getCurrentInputSourceID();
        if (currentID) {
            savedSourceID = currentID;
        }
        
        if (asciiSourceID && currentID && ![currentID isEqualToString:asciiSourceID]) {
            selectInputSource(asciiSourceID);
        }
        
        return "ascii";
    }
}

const char *im_insert(void) {
    @autoreleasepool {
        setup();
        
        if (savedSourceID && asciiSourceID && ![savedSourceID isEqualToString:asciiSourceID]) {
            selectInputSource(savedSourceID);
            return "ime";
        }
        
        return "ascii";
    }
}

void im_watch(bool enable) {
    @autoreleasepool {
        setup();
        watchEnabled = enable;
    }
}

void im_run_interactive(void (*line_handler)(const char *line)) {
    @autoreleasepool {
        setup();

        // Non-blocking so a single readiness event can drain everything.
        int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
        if (flags != -1) {
            fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
        }

        dispatch_source_t stdinSource = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_READ,
            STDIN_FILENO,
            0,
            dispatch_get_main_queue()
        );

        // Persists across events so a partial line survives until its newline.
        static char *acc = NULL;
        static size_t acc_len = 0;
        static size_t acc_cap = 0;

        dispatch_source_set_event_handler(stdinSource, ^{
            char chunk[32768];
            for (;;) {
                ssize_t n = read(STDIN_FILENO, chunk, sizeof(chunk));
                if (n > 0) {
                    if (acc_len + (size_t)n + 1 > acc_cap) {
                        size_t new_cap = acc_cap ? acc_cap : 65536;
                        while (new_cap < acc_len + (size_t)n + 1) new_cap *= 2;
                        char *grown = realloc(acc, new_cap);
                        if (!grown) {
                            // Drop what we cannot buffer rather than crash.
                            acc_len = 0;
                            continue;
                        }
                        acc = grown;
                        acc_cap = new_cap;
                    }
                    memcpy(acc + acc_len, chunk, (size_t)n);
                    acc_len += (size_t)n;

                    size_t start = 0;
                    for (size_t i = 0; i < acc_len; i++) {
                        if (acc[i] != '\n') continue;
                        size_t line_len = i - start;
                        if (line_len > 0 && acc[start + line_len - 1] == '\r') {
                            line_len--;
                        }
                        acc[start + line_len] = '\0';
                        char *line = acc + start;
                        start = i + 1;
                        if (line_len == 0) continue;
                        if (strcmp(line, "exit") == 0) {
                            dispatch_source_cancel(stdinSource);
                            CFRunLoopStop(CFRunLoopGetMain());
                            return;
                        }
                        line_handler(line);
                    }
                    if (start > 0) {
                        memmove(acc, acc + start, acc_len - start);
                        acc_len -= start;
                    }
                    continue;
                }
                if (n == 0) {
                    dispatch_source_cancel(stdinSource);
                    CFRunLoopStop(CFRunLoopGetMain());
                    return;
                }
                if (errno == EINTR) continue;
                if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                dispatch_source_cancel(stdinSource);
                CFRunLoopStop(CFRunLoopGetMain());
                return;
            }
        });

        dispatch_resume(stdinSource);
        CFRunLoopRun();
    }
}
