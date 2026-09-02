#!/bin/zsh
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
sdk_root="${NDI_SDK_DIR:-/Library/NDI SDK for Apple}"
runtime="${NDI_RUNTIME_PATH:-$sdk_root/lib/macOS/libndi.dylib}"
header="$sdk_root/include/Processing.NDI.Lib.h"
output_dir="$repo_dir/build/Release"
app="$output_dir/Sanctuary NDI.app"
entitlements="$repo_dir/NDIScreenMirror/SanctuaryNDI.entitlements"
signing_identity="${SIGNING_IDENTITY:-}"

if [[ -z "$signing_identity" ]]; then
  signing_identity="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -n 1)"
fi
if [[ -z "$signing_identity" ]]; then
  print -u2 "error: No Apple Development signing identity was found."
  print -u2 "Install a signing certificate in Keychain or set SIGNING_IDENTITY."
  exit 1
fi

if [[ ! -f "$header" ]]; then
  print -u2 "error: NDI SDK header not found at: $header"
  print -u2 "Install the NDI SDK for Apple or set NDI_SDK_DIR."
  exit 1
fi
if [[ ! -f "$runtime" ]]; then
  print -u2 "error: NDI runtime not found at: $runtime"
  print -u2 "Install the NDI SDK for Apple or set NDI_RUNTIME_PATH."
  exit 1
fi

NDI_RUNTIME_PATH="$runtime" xcodebuild \
  -project "$repo_dir/NDIScreenMirror.xcodeproj" \
  -scheme NDIScreenMirror \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$repo_dir/build/DerivedData" \
  CONFIGURATION_BUILD_DIR="$output_dir" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  DEVELOPMENT_TEAM= \
  build

[[ -d "$app" ]] || { print -u2 "error: Expected app was not produced: $app"; exit 1; }
[[ -f "$app/Contents/Frameworks/libndi.dylib" ]] || { print -u2 "error: NDI runtime is missing from app bundle"; exit 1; }

# A stable certificate-backed signature is essential for Screen Recording permission.
# Ad-hoc signatures identify each rebuild by a new code hash, causing macOS to ask again.
codesign --force --sign "$signing_identity" --options runtime --timestamp=none \
  "$app/Contents/Frameworks/libndi.dylib"
codesign --force --sign "$signing_identity" --options runtime --timestamp=none \
  --entitlements "$entitlements" "$app"

codesign --verify --deep --strict --verbose=2 "$app"
codesign -d -r- "$app" 2>&1
file "$app/Contents/MacOS/Sanctuary NDI"
file "$app/Contents/Frameworks/libndi.dylib"
otool -L "$app/Contents/MacOS/Sanctuary NDI"
otool -L "$app/Contents/Frameworks/libndi.dylib"

print
print "Release app: $app"
