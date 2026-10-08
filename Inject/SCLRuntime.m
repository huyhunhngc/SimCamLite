#import "SCLRuntime.h"
#import <objc/runtime.h>

os_log_t SCLLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("dev.ifateam.simcamlite", "inject");
    });
    return log;
}

static BOOL SCLSwizzle(Class cls, SEL original, SEL replacement) {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    if (!originalMethod || !replacementMethod) {
        SCLLogError("Swizzle skipped %{public}s -[%{public}s]", class_getName(cls), sel_getName(original));
        return NO;
    }
    if (class_addMethod(cls, original, method_getImplementation(replacementMethod), method_getTypeEncoding(replacementMethod))) {
        class_replaceMethod(cls, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
    return YES;
}

BOOL SCLSwizzleInstance(Class cls, SEL original, SEL replacement) {
    return SCLSwizzle(cls, original, replacement);
}

BOOL SCLSwizzleClass(Class cls, SEL original, SEL replacement) {
    return SCLSwizzle(object_getClass(cls), original, replacement);
}

void SCLLeakObject(id object) {
    if (object) {
        (void)CFBridgingRetain(object);
    }
}

@implementation SCLWeakBox

+ (instancetype)boxWithValue:(id)value {
    SCLWeakBox *box = [SCLWeakBox new];
    box.value = value;
    return box;
}

@end
