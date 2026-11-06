#ifndef MESA_MOUSE_BRIDGE_H
#define MESA_MOUSE_BRIDGE_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>
bool MBInitialize(void);
bool MBDockSwipeAvailable(void);
uint32_t MBTargetDeviceCount(void);
bool MBTargetConnected(uint64_t sender);
uint64_t MBEventSender(CGEventRef event);
bool MBReadWheel(CGEventRef event, uint64_t *sender, double *rawX, double *rawY);
bool MBPostDockSwipe(uint32_t phase, double progress, double velocity);
bool MBPrepareDockSwipe(void);
bool MBDockNotification(CFStringRef name);
#endif
