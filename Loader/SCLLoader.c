#include <dlfcn.h>
#include <libgen.h>
#include <mach-o/dyld.h>
#include <os/log.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

__attribute__((constructor))
static void SCLLoaderInit(void) {
    if (getenv("SIMCAMLITE_DISABLE")) {
        return;
    }

    char executable[4096];
    uint32_t size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &size) != 0) {
        return;
    }

    int forced = getenv("SIMCAMLITE_FORCE") != NULL;
    int isUserApp = strstr(executable, "/Containers/Bundle/Application/") != NULL
        && strstr(executable, ".appex/") == NULL;
    if (!forced && !isUserApp) {
        return;
    }

    Dl_info info;
    if (!dladdr((const void *)SCLLoaderInit, &info) || !info.dli_fname) {
        return;
    }

    char loaderPath[4096];
    strlcpy(loaderPath, info.dli_fname, sizeof(loaderPath));
    char frameworkPath[4096];
    snprintf(frameworkPath, sizeof(frameworkPath), "%s/SimCamLiteInject.framework/SimCamLiteInject", dirname(loaderPath));

    if (!dlopen(frameworkPath, RTLD_NOW)) {
        os_log_error(OS_LOG_DEFAULT, "[SimCamLite] Failed to load %{public}s: %{public}s", frameworkPath, dlerror());
    }
}
