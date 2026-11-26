#!/usr/bin/env bash
# Build notchprompt from source and lock it inside the macOS App Sandbox.
#
#   scripts/sandboxed.sh build     build + sign + verify (default)
#   scripts/sandboxed.sh run       build, then launch the sandboxed app
#   scripts/sandboxed.sh install   build, then copy it to /Applications
#   scripts/sandboxed.sh verify    re-check an already built or installed app
#
# Every step fails closed: if the app is not sandboxed with exactly the
# permissions in scripts/sandbox.entitlements, the script stops with an error
# instead of producing something runnable.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT_DIR/scripts/sandbox.entitlements"
DERIVED_DATA_PATH="$ROOT_DIR/build/local"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/notchprompt.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
BUNDLE_ID="notch.notchprompt"
MIN_MACOS_MAJOR=14

# The app source was security-reviewed at this commit (upstream
# saif0200/notchprompt). The build refuses to compile anything else unless
# ALLOW_UNREVIEWED=1 is set.
REVIEWED_COMMIT="bbe1e19a8610986efd3a6c0ff52966d8138ad577"

EXPECTED_ENTITLEMENTS=(
  "com.apple.security.app-sandbox"
  "com.apple.security.files.user-selected.read-write"
)

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

die() { echo "error: $*" >&2; exit 1; }
step() { echo "==> $*"; }

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "notchprompt is a macOS app; run this on a Mac (it cannot run in Docker or on Linux)."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= MIN_MACOS_MAJOR )) || die "macOS ${MIN_MACOS_MAJOR}.0 or newer is required (this Mac has $(sw_vers -productVersion))."
  xcodebuild -version >/dev/null 2>&1 || die "Full Xcode is required (Command Line Tools alone cannot build apps).
  Install Xcode from the App Store, open it once, then run:
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
}

check_source() {
  step "Checking app source matches the reviewed commit ${REVIEWED_COMMIT:0:7}"
  local problem=""
  if ! git -C "$ROOT_DIR" cat-file -e "${REVIEWED_COMMIT}^{commit}" 2>/dev/null; then
    problem="reviewed commit not present in this clone"
  elif ! git -C "$ROOT_DIR" diff --quiet "$REVIEWED_COMMIT" -- notchprompt notchprompt.xcodeproj/project.pbxproj; then
    problem="tracked app source differs from the reviewed commit"
  else
    # Xcode compiles every file in notchprompt/ (synchronized folder), so
    # untracked or git-ignored files there would be built too.
    local extra
    extra="$(git -C "$ROOT_DIR" ls-files --others -- notchprompt | grep -v '\.DS_Store$' || true)"
    [[ -z "$extra" ]] || problem="unreviewed files in notchprompt/: ${extra//$'\n'/, }"
  fi

  if [[ -n "$problem" ]]; then
    if [[ "${ALLOW_UNREVIEWED:-0}" == "1" ]]; then
      echo "warning: ${problem}; continuing because ALLOW_UNREVIEWED=1" >&2
    else
      die "${problem}.
  Review the changes (git diff ${REVIEWED_COMMIT:0:7} -- notchprompt) and, if you trust them,
  rerun with ALLOW_UNREVIEWED=1 or update REVIEWED_COMMIT in this script."
    fi
  fi
}

build_app() {
  step "Building Release app from source"
  rm -rf "$APP_PATH"
  # Same unsigned build the upstream release CI uses; signing happens below
  # with an explicit entitlements file so the sandbox cannot be dropped.
  xcodebuild \
    -project "$ROOT_DIR/notchprompt.xcodeproj" \
    -scheme notchprompt \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -quiet \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    build
  [[ -d "$APP_PATH" ]] || die "build finished but no app at $APP_PATH"

  step "Signing locally (ad-hoc) with App Sandbox + hardened runtime"
  codesign --force --sign - --options runtime --entitlements "$ENTITLEMENTS" "$APP_PATH"
}

verify_app() {
  local app="$1"
  step "Verifying $app"
  [[ -d "$app" ]] || die "no app at $app (run: scripts/sandboxed.sh build)"

  codesign --verify --strict "$app" || die "code signature is invalid"

  local id
  id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
  [[ "$id" == "$BUNDLE_ID" ]] || die "unexpected bundle id '$id'"

  # Only the main binary may be executable: no helper tools, XPC services or
  # login items that could run outside the app's own sandboxed process.
  local exe executables
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
  executables="$(find "$app/Contents" -type f -perm -u+x)"
  [[ "$executables" == "$app/Contents/MacOS/$exe" ]] || die "unexpected executables in bundle:
$executables"

  local sig_info
  sig_info="$(codesign -d --verbose=2 "$app" 2>&1)"
  grep -Eq '^CodeDirectory.*flags=.*runtime' <<<"$sig_info" \
    || die "hardened runtime is not enabled"

  local ents="$TMP_DIR/entitlements.plist"
  codesign -d --entitlements - --xml "$app" > "$ents" 2>/dev/null || die "could not read entitlements"
  [[ -s "$ents" ]] || die "app has no entitlements, so it is NOT sandboxed"

  local key
  for key in "${EXPECTED_ENTITLEMENTS[@]}"; do
    # PlistBuddy, not plutil -extract: plutil treats the dots in the key as a path.
    [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$ents" 2>/dev/null)" == "true" ]] \
      || die "missing entitlement $key"
  done
  local count
  count="$(plutil -convert xml1 -o - "$ents" | grep -c '<key>' || true)"
  (( count == ${#EXPECTED_ENTITLEMENTS[@]} )) \
    || die "app has extra entitlements beyond sandbox + user-selected files:
$(plutil -p "$ents")"

  echo "    OK: sandboxed, no network access, only files you pick, hardened runtime"
}

confirm_running_sandboxed() {
  # macOS creates the container on the first sandboxed launch. If sandbox
  # setup ever failed, the app would exit at launch rather than run unconfined.
  local container="$HOME/Library/Containers/$BUNDLE_ID"
  local _
  for _ in {1..15}; do
    if [[ -d "$container" ]] && pgrep -xq notchprompt; then
      echo "    Running inside its sandbox container: $container"
      echo "    (Activity Monitor > View > Columns > Sandbox shows 'Yes' for notchprompt.)"
      return
    fi
    sleep 1
  done
  echo "warning: could not confirm the sandbox container yet; check Activity Monitor's Sandbox column." >&2
}

cmd="${1:-build}"
case "$cmd" in
  build)
    require_macos; check_source; build_app; verify_app "$APP_PATH"
    echo "Built: $APP_PATH"
    ;;
  run)
    require_macos; check_source; build_app; verify_app "$APP_PATH"
    step "Launching"
    open "$APP_PATH"
    confirm_running_sandboxed
    ;;
  install)
    require_macos; check_source; build_app; verify_app "$APP_PATH"
    target="$INSTALL_DIR/notchprompt.app"
    if [[ -e "$target" ]]; then
      pkill -x notchprompt 2>/dev/null || true
      step "Replacing existing $target"
      rm -rf "$target"
    fi
    ditto "$APP_PATH" "$target"
    verify_app "$target"
    echo "Installed: $target"
    ;;
  verify)
    require_macos
    if [[ -n "${2:-}" ]]; then
      verify_app "$2"
    else
      verify_app "$APP_PATH"
    fi
    ;;
  *)
    die "unknown command '$cmd' (use: build | run | install | verify [path/to/notchprompt.app])"
    ;;
esac
