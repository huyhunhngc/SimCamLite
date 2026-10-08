#import "SCLRuntime.h"
#import <objc/runtime.h>

#if __has_feature(objc_arc)
#error "SCLRuntimeMRC.m must be compiled with -fno-objc-arc"
#endif

static void SCLSafeDealloc(id self, SEL _cmd) {
    object_dispose(self);
}

void SCLInstallSafeDealloc(Class cls) {
    class_addMethod(cls, sel_registerName("dealloc"), (IMP)SCLSafeDealloc, "v@:");
}
