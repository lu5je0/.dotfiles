#import <Carbon/Carbon.h>
#import <AppKit/AppKit.h>
#include <stdbool.h>
#include <sys/sysctl.h>
#include <unistd.h>

#include "../im.h"

static NSString *asciiSourceID = nil;
static NSString *lastNonAsciiSourceID = nil;
static BOOL isNormalMode = NO;
static BOOL isFrontmost = NO;
static BOOL initialized = NO;
static BOOL keeperEnabled = NO;
static pid_t terminalPID = 0;

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

static pid_t getParentTerminalPID(void) {
    pid_t pid = getppid();
    while (pid > 1) {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (app && app.activationPolicy == NSApplicationActivationPolicyRegular) {
            return pid;
        }
        struct kinfo_proc info;
        size_t size = sizeof(info);
        int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
        if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
            return 0;
        }
        pid_t ppid = info.kp_eproc.e_ppid;
        if (ppid == pid) return 0;
        pid = ppid;
    }
    return 0;
}

static BOOL isMyTerminal(NSRunningApplication *app) {
    if (terminalPID == 0) {
        terminalPID = getParentTerminalPID();
    }
    return app.processIdentifier == terminalPID;
}

static void inputSourceChanged(CFNotificationCenterRef center,
                               void *observer,
                               CFNotificationName name,
                               const void *object,
                               CFDictionaryRef userInfo) {
    if (!keeperEnabled || !isFrontmost) return;
    
    NSString *currentID = getCurrentInputSourceID();
    if (asciiSourceID && ![currentID isEqualToString:asciiSourceID]) {
        if (currentID) {
            lastNonAsciiSourceID = currentID;
        }
        selectInputSource(asciiSourceID);
    }
}

static void appDidActivate(CFNotificationCenterRef center,
                          void *observer,
                          CFNotificationName name,
                          const void *object,
                          CFDictionaryRef userInfo) {
    NSRunningApplication *app = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (app) {
        isFrontmost = isMyTerminal(app);
    }
}

static void appDidDeactivate(CFNotificationCenterRef center,
                            void *observer,
                            CFNotificationName name,
                            const void *object,
                            CFDictionaryRef userInfo) {
    NSRunningApplication *app = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (app && isMyTerminal(app)) {
        isFrontmost = NO;
    }
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
    
    // Monitor app activation via NSWorkspace notifications
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidActivateApplicationNotification
                                                                    object:nil
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *note) {
        NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
        if (app) {
            isFrontmost = isMyTerminal(app);
        }
    }];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidDeactivateApplicationNotification
                                                                    object:nil
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *note) {
        NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
        if (app && isMyTerminal(app)) {
            isFrontmost = NO;
        }
    }];
    
    // Check if terminal is already frontmost
    NSRunningApplication *frontApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
    if (frontApp) {
        isFrontmost = isMyTerminal(frontApp);
    }
}

const char *im_normal(void) {
    @autoreleasepool {
        setup();
        
        NSString *currentID = getCurrentInputSourceID();
        if (currentID && asciiSourceID && ![currentID isEqualToString:asciiSourceID]) {
            lastNonAsciiSourceID = currentID;
        }
        
        isNormalMode = YES;
        
        if (asciiSourceID) {
            selectInputSource(asciiSourceID);
        }
        
        return "eng";
    }
}

const char *im_insert(void) {
    @autoreleasepool {
        setup();
        
        isNormalMode = NO;
        
        if (lastNonAsciiSourceID) {
            selectInputSource(lastNonAsciiSourceID);
            return "chi";
        }
        
        return "eng";
    }
}

void im_keeper(bool enable) {
    @autoreleasepool {
        setup();
        keeperEnabled = enable;
        // keeper(false) 时不取消监听，只在 inputSourceChanged 中判断 isNormalMode
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
