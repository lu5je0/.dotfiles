#include <CoreFoundation/CoreFoundation.h>
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <unistd.h>

static void notification_callback(CFNotificationCenterRef center,
                                   void *observer,
                                   CFStringRef name,
                                   const void *object,
                                   CFDictionaryRef userInfo) {
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (!source) return;

    CFStringRef sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    if (sourceID) {
        char buf[256];
        if (CFStringGetCString(sourceID, buf, sizeof(buf), kCFStringEncodingUTF8)) {
            printf("%s\n", buf);
            fflush(stdout);
        }
    }
    CFRelease(source);
}

int main(void) {
    CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
    CFNotificationCenterAddObserver(
        center,
        NULL,
        notification_callback,
        CFSTR("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    CFRunLoopRun();
    return 0;
}
