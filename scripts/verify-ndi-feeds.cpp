// Manual integration check. Receives frames without saving any screen contents.
// clang++ -std=c++17 -I"/Library/NDI SDK for Apple/include" scripts/verify-ndi-feeds.cpp \
//   -L"/Library/NDI SDK for Apple/lib/macOS" -lndi \
//   -Wl,-rpath,"/Library/NDI SDK for Apple/lib/macOS" -o /tmp/verify-ndi-feeds
// /tmp/verify-ndi-feeds "HOST (Sanctuary Projector Screen)" "HOST (Sanctuary User Screen)"
#include <cstddef>
#include <Processing.NDI.Lib.h>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <vector>
#include <set>
#include <string>

int main(int argc, char** argv) {
    if (!NDIlib_initialize()) return 2;
    auto finder = NDIlib_find_create_v2();
    if (!finder) return 2;
    std::vector<NDIlib_recv_instance_t> receivers(argc - 1, nullptr);
    std::vector<bool> received(argc - 1, false);
    std::set<std::string> discovered;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(argc == 1 ? 3 : 25);
    while (std::chrono::steady_clock::now() < deadline) {
        uint32_t count = 0;
        const auto* sources = NDIlib_find_get_current_sources(finder, &count);
        if (argc == 1) {
            for (uint32_t j = 0; j < count; ++j) {
                if (discovered.insert(sources[j].p_ndi_name).second) std::puts(sources[j].p_ndi_name);
            }
            NDIlib_find_wait_for_sources(finder, 100);
            continue;
        }
        for (int i = 0; i < argc - 1; ++i) {
            if (!receivers[i]) {
                for (uint32_t j = 0; j < count; ++j) {
                    if (std::strcmp(sources[j].p_ndi_name, argv[i + 1]) != 0) continue;
                    NDIlib_recv_create_v3_t config;
                    config.source_to_connect_to = sources[j];
                    config.bandwidth = NDIlib_recv_bandwidth_highest;
                    receivers[i] = NDIlib_recv_create_v3(&config);
                    break;
                }
            }
            if (receivers[i] && !received[i]) {
                NDIlib_video_frame_v2_t frame;
                if (NDIlib_recv_capture_v3(receivers[i], &frame, nullptr, nullptr, 100) == NDIlib_frame_type_video) {
                    received[i] = frame.xres > 0 && frame.yres > 0 && frame.p_data;
                    std::printf("%s: video %dx%d\n", argv[i + 1], frame.xres, frame.yres);
                    NDIlib_recv_free_video_v2(receivers[i], &frame);
                }
            }
        }
        bool done = true;
        for (bool value : received) done &= value;
        if (done) break;
        NDIlib_find_wait_for_sources(finder, 100);
    }
    bool passed = true;
    for (int i = 0; i < argc - 1; ++i) {
        if (!received[i]) { std::fprintf(stderr, "No video: %s\n", argv[i + 1]); passed = false; }
        if (receivers[i]) NDIlib_recv_destroy(receivers[i]);
    }
    NDIlib_find_destroy(finder);
    NDIlib_destroy();
    return passed ? 0 : 1;
}
