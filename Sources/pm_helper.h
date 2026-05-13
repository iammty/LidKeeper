#ifndef PM_HELPER_H
#define PM_HELPER_H

#include <stdint.h>

// Creates a kIOPMAssertionTypeNoIdleSleep assertion.
// Returns assertion ID on success (> 0), 0 on failure.
uint32_t pm_no_idle_sleep(const char *reason);

// Releases a power management assertion.
// Returns 0 on success, -1 on failure.
int pm_release_assertion(uint32_t id);

#endif
