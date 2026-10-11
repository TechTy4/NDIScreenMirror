// Deliberately fail initialization once, as can happen during startup.
#include <stdbool.h>
#include <stddef.h>
static int attempts;
bool NDIlib_initialize(void) { return ++attempts > 1; }
void NDIlib_destroy(void) {}
const char *NDIlib_version(void) { return "Retry test runtime"; }
void *NDIlib_send_create(const void *settings) { return NULL; }
void NDIlib_send_destroy(void *sender) {}
void NDIlib_send_send_video_v2(void *sender, const void *frame) {}
int NDIlib_send_get_no_connections(void *sender, unsigned int timeout) { return 0; }
