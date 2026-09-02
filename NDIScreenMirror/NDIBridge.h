#pragma once

#include <CoreVideo/CoreVideo.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SNDISender SNDISender;

/// Dynamically loads the official NDI runtime and creates a High Bandwidth sender.
SNDISender * _Nullable SNDISenderCreate(const char * _Nonnull name,
                                        char * _Nullable error,
                                        int errorCapacity);
void SNDISenderDestroy(SNDISender * _Nullable sender);

/// Sends one CVPixelBuffer in native BGRA layout. The call is synchronous.
bool SNDISenderSendPixelBuffer(SNDISender * _Nonnull sender,
                              CVPixelBufferRef _Nonnull pixelBuffer,
                              int frameRateNumerator,
                              int frameRateDenominator,
                              int64_t timecode100ns);
int SNDISenderConnectionCount(SNDISender * _Nonnull sender);
const char * _Nonnull SNDIRuntimeVersion(void);
bool SNDIRuntimeIsAvailable(void);

#ifdef __cplusplus
}
#endif
