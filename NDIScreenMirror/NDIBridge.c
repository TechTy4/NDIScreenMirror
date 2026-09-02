#include "NDIBridge.h"
#include <Processing.NDI.Lib.h>

#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef bool (*ndi_initialize_fn)(void);
typedef void (*ndi_destroy_fn)(void);
typedef const char *(*ndi_version_fn)(void);
typedef NDIlib_send_instance_t (*ndi_send_create_fn)(const NDIlib_send_create_t *);
typedef void (*ndi_send_destroy_fn)(NDIlib_send_instance_t);
typedef void (*ndi_send_video_fn)(NDIlib_send_instance_t, const NDIlib_video_frame_v2_t *);
typedef int (*ndi_connections_fn)(NDIlib_send_instance_t, uint32_t);

typedef struct {
    void *library;
    ndi_initialize_fn initialize;
    ndi_destroy_fn destroy;
    ndi_version_fn version;
    ndi_send_create_fn send_create;
    ndi_send_destroy_fn send_destroy;
    ndi_send_video_fn send_video;
    ndi_connections_fn connections;
    bool initialized;
} NDIAPI;

struct SNDISender {
    NDIlib_send_instance_t instance;
};

static NDIAPI api;

static void copy_error(char *error, int capacity, const char *message) {
    if (error && capacity > 0) {
        snprintf(error, (size_t)capacity, "%s", message ? message : "Unknown NDI error");
    }
}

static bool load_symbol(void **target, const char *name) {
    *target = dlsym(api.library, name);
    return *target != NULL;
}

static bool load_api(void) {
    if (api.library) return api.initialized;

    // Receiver discovery probes may connect and immediately close. The NDI
    // runtime writes to those sockets; ignore SIGPIPE so a receiver disconnect
    // is reported as a socket error instead of terminating the broadcaster.
    signal(SIGPIPE, SIG_IGN);

    char executable[PATH_MAX];
    uint32_t size = sizeof(executable);
    char bundled[PATH_MAX] = {0};
    if (_NSGetExecutablePath(executable, &size) == 0) {
        char *slash = strrchr(executable, '/');
        if (slash) {
            *slash = '\0';
            snprintf(bundled, sizeof(bundled), "%s/../Frameworks/libndi.dylib", executable);
        }
    }

    const char *paths[] = {
        bundled[0] ? bundled : NULL,
        "@rpath/libndi.dylib",
        "/usr/local/lib/libndi.dylib",
        NULL
    };
    for (int i = 0; paths[i]; ++i) {
        api.library = dlopen(paths[i], RTLD_NOW | RTLD_LOCAL);
        if (api.library) break;
    }
    if (!api.library) return false;

    if (!load_symbol((void **)&api.initialize, "NDIlib_initialize") ||
        !load_symbol((void **)&api.destroy, "NDIlib_destroy") ||
        !load_symbol((void **)&api.version, "NDIlib_version") ||
        !load_symbol((void **)&api.send_create, "NDIlib_send_create") ||
        !load_symbol((void **)&api.send_destroy, "NDIlib_send_destroy") ||
        !load_symbol((void **)&api.send_video, "NDIlib_send_send_video_v2") ||
        !load_symbol((void **)&api.connections, "NDIlib_send_get_no_connections")) {
        dlclose(api.library);
        memset(&api, 0, sizeof(api));
        return false;
    }
    api.initialized = api.initialize();
    return api.initialized;
}

bool SNDIRuntimeIsAvailable(void) { return load_api(); }

const char *SNDIRuntimeVersion(void) {
    return load_api() && api.version ? api.version() : "Unavailable";
}

SNDISender *SNDISenderCreate(const char *name, char *error, int errorCapacity) {
    if (!load_api()) {
        copy_error(error, errorCapacity, "The NDI runtime could not be loaded.");
        return NULL;
    }
    if (!name || !name[0]) {
        copy_error(error, errorCapacity, "The NDI source name cannot be empty.");
        return NULL;
    }
    NDIlib_send_create_t config = {
        .p_ndi_name = name,
        .p_groups = NULL,
        .clock_video = true,
        .clock_audio = false
    };
    NDIlib_send_instance_t instance = api.send_create(&config);
    if (!instance) {
        copy_error(error, errorCapacity, "The NDI sender could not be created.");
        return NULL;
    }
    SNDISender *sender = calloc(1, sizeof(SNDISender));
    if (!sender) {
        api.send_destroy(instance);
        copy_error(error, errorCapacity, "Not enough memory to create the NDI sender.");
        return NULL;
    }
    sender->instance = instance;
    return sender;
}

void SNDISenderDestroy(SNDISender *sender) {
    if (!sender) return;
    if (sender->instance && api.send_destroy) api.send_destroy(sender->instance);
    free(sender);
}

bool SNDISenderSendPixelBuffer(SNDISender *sender, CVPixelBufferRef buffer,
                              int frameRateNumerator, int frameRateDenominator,
                              int64_t timecode100ns) {
    if (!sender || !sender->instance || !buffer || !api.send_video) return false;
    if (CVPixelBufferGetPixelFormatType(buffer) != kCVPixelFormatType_32BGRA) return false;
    if (CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) return false;

    NDIlib_video_frame_v2_t frame = {
        .xres = (int)CVPixelBufferGetWidth(buffer),
        .yres = (int)CVPixelBufferGetHeight(buffer),
        .FourCC = NDIlib_FourCC_video_type_BGRA,
        .frame_rate_N = frameRateNumerator,
        .frame_rate_D = frameRateDenominator,
        .picture_aspect_ratio = (float)CVPixelBufferGetWidth(buffer) / (float)CVPixelBufferGetHeight(buffer),
        .frame_format_type = NDIlib_frame_format_type_progressive,
        .timecode = timecode100ns,
        .p_data = CVPixelBufferGetBaseAddress(buffer),
        .line_stride_in_bytes = (int)CVPixelBufferGetBytesPerRow(buffer),
        .p_metadata = NULL,
        .timestamp = 0
    };
    api.send_video(sender->instance, &frame);
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    return true;
}

int SNDISenderConnectionCount(SNDISender *sender) {
    return sender && sender->instance && api.connections ? api.connections(sender->instance, 0) : 0;
}
