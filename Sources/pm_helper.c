#include "pm_helper.h"
#include <IOKit/pwr_mgt/IOPMLib.h>

uint32_t pm_no_idle_sleep(const char *reason) {
    IOPMAssertionID assertionID = 0;
    CFStringRef reasonStr = CFStringCreateWithCString(
        kCFAllocatorDefault, reason, kCFStringEncodingUTF8);
    if (!reasonStr) return 0;

    IOReturn ret = IOPMAssertionCreateWithName(
        kIOPMAssertionTypeNoIdleSleep,
        kIOPMAssertionLevelOn,
        reasonStr,
        &assertionID);

    CFRelease(reasonStr);
    return ret == kIOReturnSuccess ? assertionID : 0;
}

int pm_release_assertion(uint32_t id) {
    if (id == 0) return 0;
    return IOPMAssertionRelease(id) == kIOReturnSuccess ? 0 : -1;
}
