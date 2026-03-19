#include <CoreFoundation/CoreFoundation.h>
#include <Carbon/Carbon.h>
#include <string.h>

static char last_ime[256] = {0};

static void notification_callback(CFNotificationCenterRef center,
                                   void *observer,
                                   CFStringRef name,
                                   const void *object,
                                   CFDictionaryRef userInfo) {
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (!source) return;

    CFStringRef sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
    if (sourceID) {
        CFStringGetCString(sourceID, last_ime, sizeof(last_ime), kCFStringEncodingUTF8);
    }
    CFRelease(source);
}

void ime_notify_setup(void) {
    CFNotificationCenterRef center = CFNotificationCenterGetDistributedCenter();
    CFNotificationCenterAddObserver(
        center,
        NULL,
        notification_callback,
        CFSTR("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}

// Drive the run loop to process pending notifications (call from main thread)
void ime_notify_poll(double timeout_seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout_seconds, true);
}

// Read the last notified IME (safe to call from any thread)
const char* ime_notify_get_last(void) {
    if (last_ime[0] == '\0') return NULL;
    return last_ime;
}
