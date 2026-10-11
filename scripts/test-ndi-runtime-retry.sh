#!/bin/zsh
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
sdk_root="${NDI_SDK_DIR:-/Library/NDI SDK for Apple}"
test_dir="$(mktemp -d /tmp/SanctuaryNDI-RuntimeTest.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Probe.app/Contents/MacOS" "$test_dir/Probe.app/Contents/Frameworks"
clang -dynamiclib "$repo_dir/Tests/NDIRuntimeRetry/FakeRuntime.c" \
    -o "$test_dir/Probe.app/Contents/Frameworks/libndi.dylib"
clang -I"$repo_dir/NDIScreenMirror" -I"$sdk_root/include" \
    "$repo_dir/Tests/NDIRuntimeRetry/Probe.c" "$repo_dir/NDIScreenMirror/NDIBridge.c" \
    -framework CoreVideo -framework CoreFoundation \
    -o "$test_dir/Probe.app/Contents/MacOS/probe"
"$test_dir/Probe.app/Contents/MacOS/probe"
