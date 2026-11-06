#include "MouseBridge.h"
#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <string.h>

typedef CFTypeRef HIDRef;
static HIDRef client;
static HIDRef (*clientCreate)(CFAllocatorRef);
static HIDRef (*copyServices)(HIDRef);
static HIDRef (*copyService)(HIDRef, uint64_t);
static CFTypeRef (*copyProperty)(HIDRef, CFStringRef);
static HIDRef (*copyHID)(CGEventRef);
static uint64_t (*getSender)(HIDRef);
static double (*getFloat)(HIDRef, uint32_t);
static HIDRef (*createHID)(CFAllocatorRef, uint32_t, uint64_t, uint32_t);
static void (*setInteger)(HIDRef, uint32_t, CFIndex);
static void (*setDouble)(HIDRef, uint32_t, double);
static void (*appendHID)(HIDRef, HIDRef, uint32_t);
static void (*attachHID)(CGEventRef, HIDRef);
static bool modern;
static const int64_t marker = 0x4d455341;

bool MBInitialize(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        void *cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
        void *sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (!io || !cg || !sl) return;
        clientCreate = dlsym(io, "IOHIDEventSystemClientCreate");
        copyServices = dlsym(io, "IOHIDEventSystemClientCopyServices");
        copyService = dlsym(io, "IOHIDEventSystemClientCopyServiceForRegistryID");
        copyProperty = dlsym(io, "IOHIDServiceClientCopyProperty");
        copyHID = dlsym(cg, "CGEventCopyIOHIDEvent");
        if (!copyHID) copyHID = dlsym(sl, "CGEventCopyIOHIDEvent");
        getSender = dlsym(io, "IOHIDEventGetSenderID");
        getFloat = dlsym(io, "IOHIDEventGetFloatValue");
        createHID = dlsym(io, "IOHIDEventCreate");
        setInteger = dlsym(io, "IOHIDEventSetIntegerValue");
        setDouble = dlsym(io, "IOHIDEventSetDoubleValue");
        appendHID = dlsym(io, "IOHIDEventAppendEvent");
        attachHID = dlsym(sl, "SLEventSetIOHIDEvent");
        if (clientCreate && copyServices && copyService && copyProperty && copyHID && getSender && getFloat)
            client = clientCreate(kCFAllocatorDefault);
        if (__builtin_available(macOS 27.0, *)) modern = true;
    });
    return client != NULL;
}

static int propertyInt(HIDRef service, CFStringRef key) {
    CFTypeRef value = copyProperty(service, key);
    int result = -1;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &result);
    if (value) CFRelease(value);
    return result;
}

// Any HID mouse (Generic Desktop / Mouse). Used for diagnostics only: events are not filtered by brand.
static bool target(HIDRef service) {
    return service && propertyInt(service, CFSTR("PrimaryUsagePage")) == 1 &&
        propertyInt(service, CFSTR("PrimaryUsage")) == 2;
}

uint32_t MBTargetDeviceCount(void) {
    if (!MBInitialize()) return 0;
    CFArrayRef services = (CFArrayRef)copyServices(client);
    if (!services) return 0;
    uint32_t count = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(services); i++)
        if (target(CFArrayGetValueAtIndex(services, i))) count++;
    CFRelease(services);
    return count;
}

bool MBTargetConnected(uint64_t sender) {
    if (!sender || !MBInitialize()) return false;
    HIDRef service = copyService(client, sender);
    bool matches = target(service);
    if (service) CFRelease(service);
    return matches;
}

// The HID service that produced an event (0 if unknown), e.g. to tell a mouse's key events from a keyboard's.
uint64_t MBEventSender(CGEventRef event) {
    if (!MBInitialize() || !event) return 0;
    HIDRef hid = copyHID(event);
    if (!hid) return 0;
    uint64_t sender = getSender(hid);
    CFRelease(hid);
    return sender;
}

bool MBReadWheel(CGEventRef event, uint64_t *sender, double *rawX, double *rawY) {
    if (!MBInitialize() || !event || CGEventGetType(event) != kCGEventScrollWheel) return false;
    HIDRef hid = copyHID(event);
    if (!hid) return false;
    *sender = getSender(hid);
    *rawX = getFloat(hid, 6 << 16);
    *rawY = getFloat(hid, (6 << 16) | 1);
    CFRelease(hid);
    return true;
}

// MARK: Desktop swipe
//
// The Dock switches desktops when it receives a "dock swipe" gesture event: a CGEvent of the private
// gesture type carrying the phase (began, changed, ended, cancelled), the progress in desktops and,
// when the gesture finishes, its velocity. macOS 27 reads these values from an attached IOHID event;
// earlier releases read them from private CGEvent fields and also expect a companion gesture event.

enum {
    kGestureEventType = 29,        // NSEventTypeGesture
    kDockControlEventType = 30,    // the event the Dock reacts to
    kDockSwipeHIDType = 23,        // IOHID event type for dock swipes
    kVelocityHIDType = 9,          // IOHID scroll event carrying the release velocity
    kDockSwipeHorizontal = 1,
    kDockSwipeMotionHorizontal = 3,
};

enum {  // CGEvent fields, pre-macOS 27
    kFieldType = 55,
    kFieldGestureFlags = 41,
    kFieldHIDType = 110,
    kFieldPhase = 132,
    kFieldSwipePhase = 134,
    kFieldProgress = 124,
    kFieldProgressBits = 135,
    kFieldMotionX = 119,
    kFieldMotionY = 139,
    kFieldSwipeAxis = 123,
    kFieldSwipeMotion = 165,
    kFieldInvertedFlag = 136,
    kFieldVelocityX = 129,
    kFieldVelocityY = 130,
};
static const int64_t kGestureFlags = 33231;

static uint32_t hidField(uint32_t type, uint32_t index) { return (type << 16) | index; }
static bool finishesGesture(uint32_t phase) { return phase == 4 || phase == 8; }

bool MBDockSwipeAvailable(void) {
    if (!MBInitialize()) return false;
    return !modern || (createHID && setInteger && setDouble && appendHID && attachHID);
}

static bool attachHIDSwipe(CGEventRef event, uint32_t phase, double progress, double velocity) {
    HIDRef swipe = createHID(NULL, kDockSwipeHIDType, 0, phase << 24);
    if (!swipe) return false;
    setInteger(swipe, hidField(kDockSwipeHIDType, 1), kDockSwipeHorizontal);
    setInteger(swipe, hidField(kDockSwipeHIDType, 5), kDockSwipeMotionHorizontal);
    setDouble(swipe, hidField(kDockSwipeHIDType, 2), progress);
    if (finishesGesture(phase)) {
        HIDRef release = createHID(NULL, kVelocityHIDType, 0, 0);
        if (!release) { CFRelease(swipe); return false; }
        setDouble(release, hidField(kVelocityHIDType, 0), velocity);
        setDouble(release, hidField(kVelocityHIDType, 1), velocity);
        setDouble(release, hidField(kVelocityHIDType, 2), 0);
        appendHID(swipe, release, 0);
        CFRelease(release);
    }
    attachHID(event, swipe);
    CFRelease(swipe);
    return true;
}

static float floatFromBits(uint32_t bits) { float value; memcpy(&value, &bits, sizeof value); return value; }
static uint32_t bitsFromFloat(float value) { uint32_t bits; memcpy(&bits, &value, sizeof bits); return bits; }

static void writeLegacySwipe(CGEventRef event, uint32_t phase, double progress, double velocity) {
    struct { CGEventField field; int64_t value; } integers[] = {
        { kFieldGestureFlags, kGestureFlags }, { kFieldHIDType, kDockSwipeHIDType },
        { kFieldPhase, phase }, { kFieldSwipePhase, phase },
        { kFieldProgressBits, bitsFromFloat((float)progress) },
        { kFieldSwipeAxis, 1 }, { kFieldSwipeMotion, 1 }, { kFieldInvertedFlag, 0 },
    };
    for (size_t i = 0; i < sizeof integers / sizeof *integers; i++)
        CGEventSetIntegerValueField(event, integers[i].field, integers[i].value);
    double smallestMotion = floatFromBits(1);  // a non-zero motion the Dock accepts
    CGEventSetDoubleValueField(event, kFieldProgress, progress);
    CGEventSetDoubleValueField(event, kFieldMotionX, smallestMotion);
    CGEventSetDoubleValueField(event, kFieldMotionY, smallestMotion);
    CGEventSetDoubleValueField(event, kFieldVelocityX, velocity);
    CGEventSetDoubleValueField(event, kFieldVelocityY, velocity);
}

static CGEventRef newMarkedEvent(int64_t type) {
    CGEventRef event = CGEventCreate(NULL);
    if (!event) return NULL;
    CGEventSetIntegerValueField(event, kFieldType, type);
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, marker);
    return event;
}

static CGEventRef newDockSwipe(uint32_t phase, double progress, double velocity) {
    if (!MBDockSwipeAvailable() || !isfinite(progress) || !isfinite(velocity)) return NULL;
    CGEventRef event = newMarkedEvent(kDockControlEventType);
    if (!event) return NULL;
    if (!modern) {
        writeLegacySwipe(event, phase, progress, velocity);
    } else if (!attachHIDSwipe(event, phase, progress, velocity)) {
        CFRelease(event);
        return NULL;
    }
    return event;
}

bool MBPrepareDockSwipe(void) {
    CGEventRef probe = newDockSwipe(1, 0, 0);
    if (probe) CFRelease(probe);
    return probe != NULL;
}

bool MBPostDockSwipe(uint32_t phase, double progress, double velocity) {
    CGEventRef swipe = newDockSwipe(phase, progress, velocity);
    if (!swipe) return false;
    CGEventRef gesture = NULL;
    if (!modern) {
        gesture = newMarkedEvent(kGestureEventType);
        if (!gesture) { CFRelease(swipe); return false; }
        CGEventSetIntegerValueField(gesture, kFieldGestureFlags, kGestureFlags);
    }
    CGEventPost(kCGSessionEventTap, swipe);
    CFRelease(swipe);
    if (gesture) {
        CGEventPost(kCGSessionEventTap, gesture);
        CFRelease(gesture);
    }
    return true;
}

// Private Dock entry point for Mission Control and Show Desktop.
bool MBDockNotification(CFStringRef name) {
    static void (*send)(CFStringRef, void *);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *as = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY);
        if (as) send = dlsym(as, "CoreDockSendNotification");
    });
    if (!send) return false;
    send(name, NULL);
    return true;
}
