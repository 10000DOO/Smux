#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/release-smux.sh [archive|notarize|staple|all]

Commands:
  archive   Build a Release xcarchive, verify its signature, and create a zip.
  notarize  Submit the existing zip to Apple's notary service and wait.
  staple    Staple the accepted ticket to the archived app and recreate the zip.
  all       Run archive, notarize, and staple.

Environment:
  SMUX_PROJECT                 Xcode project path. Default: Smux.xcodeproj
  SMUX_SCHEME                  Xcode scheme. Default: Smux
  SMUX_CONFIGURATION           Xcode configuration. Default: Release
  SMUX_DESTINATION             Xcode destination. Default: generic/platform=macOS
  SMUX_RELEASE_ROOT            Release output directory. Default: build/release
  SMUX_ARCHS                   Optional Xcode ARCHS override.
  SMUX_ONLY_ACTIVE_ARCH        Optional Xcode ONLY_ACTIVE_ARCH override.
  SMUX_ENABLE_PREVIEWS         Optional Xcode ENABLE_PREVIEWS override.
  SMUX_DEVELOPMENT_TEAM        Optional Xcode DEVELOPMENT_TEAM override.
  SMUX_CODE_SIGN_STYLE         Optional Xcode CODE_SIGN_STYLE override.
  SMUX_CODE_SIGN_IDENTITY      Optional Xcode CODE_SIGN_IDENTITY override.
  SMUX_PROVISIONING_PROFILE    Optional PROVISIONING_PROFILE_SPECIFIER override.
  SMUX_OTHER_CODE_SIGN_FLAGS   Optional OTHER_CODE_SIGN_FLAGS override.

Notarization:
  SMUX_NOTARY_KEYCHAIN_PROFILE
USAGE
}

info() {
    printf '==> %s\n' "$*"
}

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

ensure_release_output_path() {
    local path="$1"
    local name="$2"
    local dir
    local real_dir
    local real_path

    case "/$path/" in
        *"/../"*|*"/./"*)
            fail "$name must not contain path traversal: $path"
            ;;
    esac

    dir="$(dirname "$path")"
    mkdir -p "$dir"
    real_dir="$(cd "$dir" && pwd -P)" || fail "cannot resolve $name: $path"
    real_path="$real_dir/$(basename "$path")"

    case "$real_path" in
        "$release_root"/*) ;;
        *) fail "$name must be inside SMUX_RELEASE_ROOT: $path" ;;
    esac
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

release_root_default="$repo_root/build/release"

project="${SMUX_PROJECT:-Smux.xcodeproj}"
scheme="${SMUX_SCHEME:-Smux}"
configuration="${SMUX_CONFIGURATION:-Release}"
destination="${SMUX_DESTINATION:-generic/platform=macOS}"
release_root_input="${SMUX_RELEASE_ROOT:-$release_root_default}"
mkdir -p "$release_root_input"
release_root="$(cd "$release_root_input" && pwd -P)"
derived_data_path="${SMUX_DERIVED_DATA_PATH:-$release_root/DerivedData}"
archive_path="${SMUX_ARCHIVE_PATH:-$release_root/Smux.xcarchive}"
app_path="${SMUX_APP_PATH:-$archive_path/Products/Applications/Smux.app}"
zip_path="${SMUX_ZIP_PATH:-$release_root/Smux.zip}"

build_setting_overrides=()
if [[ -n "${SMUX_DEVELOPMENT_TEAM:-}" ]]; then
    build_setting_overrides+=(DEVELOPMENT_TEAM="$SMUX_DEVELOPMENT_TEAM")
fi
if [[ -n "${SMUX_ARCHS:-}" ]]; then
    build_setting_overrides+=(ARCHS="$SMUX_ARCHS")
fi
if [[ -n "${SMUX_ONLY_ACTIVE_ARCH:-}" ]]; then
    build_setting_overrides+=(ONLY_ACTIVE_ARCH="$SMUX_ONLY_ACTIVE_ARCH")
fi
if [[ -n "${SMUX_ENABLE_PREVIEWS:-}" ]]; then
    build_setting_overrides+=(ENABLE_PREVIEWS="$SMUX_ENABLE_PREVIEWS")
fi
if [[ -n "${SMUX_CODE_SIGN_STYLE:-}" ]]; then
    build_setting_overrides+=(CODE_SIGN_STYLE="$SMUX_CODE_SIGN_STYLE")
fi
if [[ -n "${SMUX_CODE_SIGN_IDENTITY:-}" ]]; then
    build_setting_overrides+=(CODE_SIGN_IDENTITY="$SMUX_CODE_SIGN_IDENTITY")
fi
if [[ -n "${SMUX_PROVISIONING_PROFILE:-}" ]]; then
    build_setting_overrides+=(PROVISIONING_PROFILE_SPECIFIER="$SMUX_PROVISIONING_PROFILE")
fi
if [[ -n "${SMUX_OTHER_CODE_SIGN_FLAGS:-}" ]]; then
    build_setting_overrides+=(OTHER_CODE_SIGN_FLAGS="$SMUX_OTHER_CODE_SIGN_FLAGS")
fi

notary_credentials=()
set_notary_credentials() {
    if [[ -n "${SMUX_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        notary_credentials=(--keychain-profile "$SMUX_NOTARY_KEYCHAIN_PROFILE")
        return
    fi

    fail "notarization requires SMUX_NOTARY_KEYCHAIN_PROFILE"
}

verify_signature() {
    require_command codesign
    [[ -d "$app_path" ]] || fail "app bundle not found: $app_path"

    info "Verifying code signature"
    codesign --verify --deep --strict --verbose=2 "$app_path"
}

verify_distribution_signature() {
    require_command codesign
    [[ -d "$app_path" ]] || fail "app bundle not found: $app_path"

    codesign -dv "$app_path" 2>&1 | grep -q "Authority=Developer ID Application:" \
        || fail "notarization requires Developer ID Application signing"
}

zip_app() {
    require_command ditto
    [[ -d "$app_path" ]] || fail "app bundle not found: $app_path"
    ensure_release_output_path "$zip_path" "SMUX_ZIP_PATH"

    info "Creating notarization zip: $zip_path"
    mkdir -p "$(dirname "$zip_path")"
    rm -f -- "$zip_path"
    ditto -c -k --keepParent "$app_path" "$zip_path"
}

archive_app() {
    require_command xcodebuild

    info "Archiving $scheme ($configuration)"
    mkdir -p "$release_root"
    ensure_release_output_path "$archive_path" "SMUX_ARCHIVE_PATH"
    rm -rf -- "$archive_path"

    archive_command=(
        xcodebuild
        -project "$project" \
        -scheme "$scheme" \
        -configuration "$configuration" \
        -destination "$destination" \
        -derivedDataPath "$derived_data_path" \
        -archivePath "$archive_path" \
        archive
    )
    if [[ ${#build_setting_overrides[@]} -gt 0 ]]; then
        archive_command+=("${build_setting_overrides[@]}")
    fi

    "${archive_command[@]}"

    verify_signature
    zip_app
}

notarize_zip() {
    require_command xcrun
    [[ -f "$zip_path" ]] || fail "zip artifact not found: $zip_path"

    verify_distribution_signature
    set_notary_credentials
    info "Submitting zip for notarization"
    xcrun notarytool submit "$zip_path" --wait "${notary_credentials[@]}"
}

staple_app() {
    require_command xcrun
    [[ -d "$app_path" ]] || fail "app bundle not found: $app_path"

    info "Stapling notarization ticket"
    xcrun stapler staple "$app_path"
    xcrun stapler validate "$app_path"
    zip_app
}

command="${1:-archive}"
case "$command" in
    archive)
        archive_app
        ;;
    notarize)
        notarize_zip
        ;;
    staple)
        staple_app
        ;;
    all)
        archive_app
        notarize_zip
        staple_app
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        fail "unknown command: $command"
        ;;
esac
