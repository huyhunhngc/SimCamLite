#import <Foundation/Foundation.h>
#import "SCLFakes.h"
#import "SCLFrameReader.h"
#import "SCLHooks.h"
#import "SCLRuntime.h"

__attribute__((constructor)) static void SCLInjectInit(void) {
    @autoreleasepool {
        SCLLogInfo("Injected into %{public}@ (pid %d)", NSBundle.mainBundle.bundleIdentifier ?: @"?", getpid());
        SCLInstallFakeDeallocs();
        SCLInstallHooks();
        [SCLFrameReader.shared startHeartbeat];
    }
}
