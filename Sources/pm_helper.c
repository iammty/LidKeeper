/// Bridge to IOKit Power Management (IOPMLib) C API.
/// IOKit.pm is not exposed as a Swift submodule on macOS 14+.
/// This C file provides a thin wrapper so Swift can call it.

#include <IOKit/pwr_mgt/IOPMLib.h>
#include <stdbool.h>
#include <string.h>

/// Create a "Prevent System Sleep" assertion (strongest).
/// Prevents forced sleep from lid close on Apple Silicon.
/// Returns the assertion ID, or 0 on failure.
uint32_t pm_prevent_system_sleep(const char *reason) {
    IOPMAssertionID assertionID = kIOPMNullAssertionID;
    CFStringRef reasonStr = CFStringCreateWithCString(kCFAllocatorDefault,
                                                       reason,
                                                       kCFStringEncodingUTF8);
    if (!reasonStr) return 0;

    IOReturn ret = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventSystemSleep,
        kIOPMAssertionLevelOn,
        reasonStr,
        &assertionID
    );
    CFRelease(reasonStr);
    return (ret == kIOReturnSuccess) ? (uint32_t)assertionID : 0;
}

/// Create a "No Idle Sleep" assertion.
/// Prevents system from going to idle sleep, but allows display sleep.
/// Returns the assertion ID, or 0 on failure.
uint32_t pm_no_idle_sleep(const char *reason) {
    IOPMAssertionID assertionID = kIOPMNullAssertionID;
    CFStringRef reasonStr = CFStringCreateWithCString(kCFAllocatorDefault,
                                                       reason,
                                                       kCFStringEncodingUTF8);
    if (!reasonStr) return 0;

    IOReturn ret = IOPMAssertionCreateWithName(
        kIOPMAssertionTypeNoIdleSleep,
        kIOPMAssertionLevelOn,
        reasonStr,
        &assertionID
    );
    CFRelease(reasonStr);
    return (ret == kIOReturnSuccess) ? (uint32_t)assertionID : 0;
}

/// Release a previously created assertion.
/// Returns true on success.
bool pm_release_assertion(uint32_t assertionID) {
    if (assertionID == 0) return false;
    return (IOPMAssertionRelease((IOPMAssertionID)assertionID) == kIOReturnSuccess);
}
