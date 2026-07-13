#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 --version VERSION --build BUILD --app /path/to/FrameScript.app --output /path/to/output" >&2
}

die() {
    echo "package-release: $*" >&2
    exit 1
}

version=""
build_number=""
app_path=""
output_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            version="$2"
            shift 2
            ;;
        --build)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            build_number="$2"
            shift 2
            ;;
        --app)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            app_path="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            output_dir="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            die "unknown argument: $1"
            ;;
    esac
done

[[ -n "$version" && -n "$build_number" && -n "$app_path" && -n "$output_dir" ]] || {
    usage
    exit 2
}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must use MAJOR.MINOR.PATCH"
[[ "$build_number" =~ ^[0-9]+$ ]] || die "build number must be numeric"
[[ -d "$app_path" ]] || die "app bundle does not exist: $app_path"
[[ "$(basename "$app_path")" == "FrameScript.app" ]] || die "expected a FrameScript.app bundle"

app_parent="$(cd "$(dirname "$app_path")" && pwd -P)"
app_path="$app_parent/FrameScript.app"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd -P)"

dmg_path="$output_dir/FrameScript.dmg"
zip_path="$output_dir/FrameScript.zip"
checksums_path="$output_dir/SHA256SUMS.txt"

# Only remove files this script owns; preserve every other file in the caller's directory.
rm -f -- "$dmg_path" "$zip_path" "$checksums_path"

work_dir="$(mktemp -d "$output_dir/.framescript-package.XXXXXX")"
staging_dir="$work_dir/dmg-root"
mount_dir="$work_dir/mount"
mounted=0

cleanup() {
    if [[ "$mounted" -eq 1 ]]; then
        hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || hdiutil detach "$mount_dir" -force -quiet >/dev/null 2>&1 || true
    fi
    rm -rf -- "$work_dir"
}
trap cleanup EXIT INT TERM

info_plist="$app_path/Contents/Info.plist"
[[ -f "$info_plist" ]] || die "missing app Info.plist"

actual_version="$(plutil -extract CFBundleShortVersionString raw -o - "$info_plist")"
actual_build="$(plutil -extract CFBundleVersion raw -o - "$info_plist")"
[[ "$actual_version" == "$version" ]] || die "expected version $version, found $actual_version"
[[ "$actual_build" == "$build_number" ]] || die "expected build $build_number, found $actual_build"

executable_name="$(plutil -extract CFBundleExecutable raw -o - "$info_plist")"
executable_path="$app_path/Contents/MacOS/$executable_name"
[[ -f "$executable_path" && -x "$executable_path" ]] || die "missing main executable: $executable_path"

architectures="$(lipo -archs "$executable_path")"
for required_arch in arm64 x86_64; do
    [[ " $architectures " == *" $required_arch "* ]] || die "main executable is missing $required_arch (found: $architectures)"
done

minimum_system="$(plutil -extract LSMinimumSystemVersion raw -o - "$info_plist")"
[[ "$minimum_system" == "14.0" || "$minimum_system" == "14.0.0" ]] || die "expected LSMinimumSystemVersion 14.0, found $minimum_system"

binary_minimums="$(otool -l "$executable_path" | awk '
    $1 == "cmd" { build_version = ($2 == "LC_BUILD_VERSION"); legacy_version = ($2 == "LC_VERSION_MIN_MACOSX"); next }
    build_version && $1 == "minos" { print $2; build_version = 0; next }
    legacy_version && $1 == "version" { print $2; legacy_version = 0 }
')"
[[ -n "$binary_minimums" ]] || die "could not read the executable deployment target"
while IFS= read -r minimum; do
    [[ "$minimum" == "14.0" || "$minimum" == "14.0.0" ]] || die "expected binary deployment target 14.0, found $minimum"
done <<< "$binary_minimums"

forbidden_path="$(find "$app_path" \
    \( -name '.env' -o -name '.env.*' \
       -o -name '*.cer' -o -name '*.crt' -o -name '*.pem' -o -name '*.key' -o -name '*.p8' -o -name '*.p12' \
       -o -name '*.mobileprovision' -o -name '*.provisionprofile' -o -name '*.entitlements' \
       -o -name '.git' -o -name '.codebase-memory' -o -name 'DerivedData' -o -name 'xcuserdata' \
       -o -name '*.xcuserstate' -o -name '*.xcodeproj' -o -name '*.xcworkspace' -o -name '*.swift' \
       -o -name 'repomix-output.*' \) -print -quit)"
[[ -z "$forbidden_path" ]] || die "development or sensitive data found in app bundle: $forbidden_path"

codesign --verify --deep --strict --verbose=2 "$app_path"

mkdir -p "$staging_dir" "$mount_dir"
ditto "$app_path" "$staging_dir/FrameScript.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "FrameScript $version" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

ditto -c -k --sequesterRsrc --keepParent "$staging_dir/FrameScript.app" "$zip_path"
unzip -tq "$zip_path"
unzip -Z1 "$zip_path" | grep -Fxq 'FrameScript.app/Contents/Info.plist' || die "ZIP does not contain the FrameScript app bundle"

hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg_path" >/dev/null
mounted=1
[[ -d "$mount_dir/FrameScript.app" ]] || die "mounted DMG does not contain FrameScript.app"
[[ -L "$mount_dir/Applications" ]] || die "mounted DMG does not contain the Applications symlink"
[[ "$(readlink "$mount_dir/Applications")" == "/Applications" ]] || die "Applications symlink has the wrong target"
codesign --verify --deep --strict --verbose=2 "$mount_dir/FrameScript.app"
hdiutil detach "$mount_dir" -quiet
mounted=0

(
    cd "$output_dir"
    shasum -a 256 FrameScript.dmg FrameScript.zip > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)

echo "Created verified release artifacts in $output_dir"
