#import <Carbon/Carbon.h>
#import <AppKit/AppKit.h>
#include <stdbool.h>
#include <unistd.h>

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

    const char *state = (asciiSourceID && [currentID isEqualToString:asciiSourceID]) ? "eng" : "chi";
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
        
        return "eng";
    }
}

const char *im_insert(void) {
    @autoreleasepool {
        setup();
        
        if (savedSourceID && asciiSourceID && ![savedSourceID isEqualToString:asciiSourceID]) {
            selectInputSource(savedSourceID);
            return "chi";
        }
        
        return "eng";
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
        
        dispatch_source_t stdinSource = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_READ,
            STDIN_FILENO,
            0,
            dispatch_get_main_queue()
        );
        
        dispatch_source_set_event_handler(stdinSource, ^{
            char line[32768];
            if (fgets(line, sizeof(line), stdin)) {
                size_t len = strlen(line);
                if (len > 0 && line[len - 1] == '\n') {
                    line[len - 1] = '\0';
                    len--;
                }
                if (len > 0) {
                    if (strcmp(line, "exit") == 0) {
                        dispatch_source_cancel(stdinSource);
                        CFRunLoopStop(CFRunLoopGetMain());
                        return;
                    }
                    line_handler(line);
                }
            } else {
                // EOF
                dispatch_source_cancel(stdinSource);
                CFRunLoopStop(CFRunLoopGetMain());
            }
        });
        
        dispatch_resume(stdinSource);
        CFRunLoopRun();
    }
}
