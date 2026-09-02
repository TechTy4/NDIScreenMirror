#!/bin/zsh
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
app="$repo_dir/build/Release/Sanctuary NDI.app"
output="$repo_dir/build/Sanctuary-NDI-1.0.2-arm64.dmg"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/SanctuaryNDI.XXXXXX")"

cleanup() {
  [[ "$staging_dir" == "${TMPDIR:-/tmp}/SanctuaryNDI."* ]] && rm -rf "$staging_dir"
}
trap cleanup EXIT

[[ -d "$app" ]] || { print -u2 "error: Build the Release app first with scripts/build-release.sh"; exit 1; }
codesign --verify --deep --strict "$app"

ditto "$app" "$staging_dir/Sanctuary NDI.app"
ln -s /Applications "$staging_dir/Applications"
cp "$repo_dir/DEPLOYMENT.md" "$staging_dir/Install & Trust.md"

hdiutil create \
  -volname "Sanctuary NDI" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$output"

# On newer macOS releases diskimages-helper can hold the completed image briefly.
for attempt in {1..15}; do
  if hdiutil verify "$output"; then
    break
  fi
  if [[ "$attempt" -eq 15 ]]; then
    print -u2 "error: Could not verify the completed disk image."
    exit 1
  fi
  sleep 1
done
shasum -a 256 "$output"

print
print "Deployment image: $output"
