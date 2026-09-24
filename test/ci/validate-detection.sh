#!/usr/bin/env bash
# validate-detection.sh — runs inside CI container/VM
# Validates fx-flathub-detect.sh against a specific scenario

set -euo pipefail

SCENARIO="${1:-enabled-system}"
LIB_PATH="${LIBRARY_PATH:-/src/fx-flathub-detect.sh}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[VALIDATE]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# Source the library
if [[ ! -f "$LIB_PATH" ]]; then
    fail "Library not found at $LIB_PATH"
fi

log "Testing scenario: $SCENARIO"
log "Library: $LIB_PATH"
log "Flatpak: $(command -v flatpak || echo 'NOT INSTALLED')"
log "SELinux: ${SELINUX:-not set}"
log "AppArmor: ${APPARMOR:-not set}"

# Test helper: fixture flatpak that emulates remote-list
setup_fake_flatpak() {
    local bin_dir="$1"
    mkdir -p "$bin_dir"

    cat > "$bin_dir/flatpak" << 'EOF'
#!/usr/bin/env bash
case "$1" in
  --version) printf "1.15.8\n"; exit 0 ;;
esac
scope=""; list=""
case " $* " in
  *" --system "*) scope=system ;;
  *" --user "*)   scope=user   ;;
esac
case "$scope" in
  system) list="${RL_SYSTEM:-}" ;;
  user)   list="${RL_USER:-}"   ;;
esac
[[ "$scope" == system && "${FAIL_SYSTEM:-0}" == 1 ]] && exit 7
case " $* " in
  *" --show-disabled "*)
    case "$scope" in
      system) list="$list ${RL_SYSTEM_DISABLED:-}" ;;
      user)   list="$list ${RL_USER_DISABLED:-}"   ;;
    esac ;;
esac
if [[ " $* " == *" remote-info flathub "* ]]; then
    exit ${REMOTE_INFO_EXIT:-0}
fi
for n in $list; do printf "%s\n" "$n"; done
EOF
    chmod +x "$bin_dir/flatpak"
    export _FLATHUB_FLATPAK_SHA256="$(sha256sum "$bin_dir/flatpak" | cut -d' ' -f1)"
    export FLATPAK_TEST_MODE=1
    export PATH="$bin_dir:$PATH"
}

# Test helper: write a repo config file
write_config() {
    local path="$1"
    shift
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "[core]" "repo_version=1" "$@" > "$path"
}

# Source library
source "$LIB_PATH"

# --- Test Cases ---

case "$SCENARIO" in
    enabled-system)
        log "Setting up: Flathub enabled in system scope"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export RL_SYSTEM="flathub"
        export RL_USER=""

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 0 ]] || fail "flathub_enabled should be true"
        [[ "$FLATHUB_ENABLED" == "1" ]] || fail "FLATHUB_ENABLED=1 expected"
        [[ "$FLATHUB_STATE" == "enabled" ]] || fail "FLATHUB_STATE=enabled expected"
        [[ "$FLATHUB_SCOPE" == "system" ]] || fail "FLATHUB_SCOPE=system expected"
        [[ "$FLATHUB_BIN" == "$FP_BIN/flatpak" ]] || fail "FLATHUB_BIN mismatch"
        log "PASS: enabled-system"
        ;;

    enabled-user)
        log "Setting up: Flathub enabled in user scope"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export RL_SYSTEM=""
        export RL_USER="flathub"

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 0 ]] || fail "flathub_enabled should be true"
        [[ "$FLATHUB_STATE" == "enabled" ]] || fail "FLATHUB_STATE=enabled expected"
        [[ "$FLATHUB_SCOPE" == "user" ]] || fail "FLATHUB_SCOPE=user expected"
        log "PASS: enabled-user"
        ;;

    enabled-both)
        log "Setting up: Flathub enabled in both scopes"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export RL_SYSTEM="flathub"
        export RL_USER="flathub"

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 0 ]] || fail "flathub_enabled should be true"
        [[ "$FLATHUB_STATE" == "enabled" ]] || fail "FLATHUB_STATE=enabled expected"
        [[ "$FLATHUB_SCOPE" == "both" ]] || fail "FLATHUB_SCOPE=both expected"
        log "PASS: enabled-both"
        ;;

    disabled-system)
        log "Setting up: Flathub disabled in system scope"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export RL_SYSTEM=""
        export RL_SYSTEM_DISABLED="flathub"
        export RL_USER=""

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 1 ]] || fail "flathub_enabled should be false"
        [[ "$FLATHUB_STATE" == "disabled" ]] || fail "FLATHUB_STATE=disabled expected"
        log "PASS: disabled-system"
        ;;

    disabled-user)
        log "Setting up: Flathub disabled in user scope"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export RL_SYSTEM=""
        export RL_USER_DISABLED="flathub"
        export RL_USER=""

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 1 ]] || fail "flathub_enabled should be false"
        [[ "$FLATHUB_STATE" == "disabled" ]] || fail "FLATHUB_STATE=disabled expected"
        log "PASS: disabled-user"
        ;;

    not-configured)
        log "Setting up: Flathub not configured"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export RL_SYSTEM=""
        export RL_USER=""

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 1 ]] || fail "flathub_enabled should be false"
        [[ "$FLATHUB_STATE" == "not-configured" ]] || fail "FLATHUB_STATE=not-configured expected"
        scope=$(flathub_scope)
        [[ "$scope" == "empty" ]] || fail "flathub_scope=empty expected (got: $scope)"
        log "PASS: not-configured"
        ;;

    flatpak-missing)
        log "Setting up: flatpak binary absent"
        export _FLATHUB_SYSTEM_CONFIG="$(mktemp -d)/none-system"
        export _FLATHUB_USER_CONFIG="$(mktemp -d)/none-user"
        export FLATPAK_TEST_MODE=1
        PATH="/nonexistent-bin-dir"
        export PATH

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 1 ]] || fail "flathub_enabled should be false"
        [[ "$FLATHUB_STATE" == "flatpak-missing" ]] || fail "FLATHUB_STATE=flatpak-missing expected"
        [[ -z "$FLATHUB_BIN" ]] || fail "FLATHUB_BIN should be empty"
        log "PASS: flatpak-missing"
        ;;

    file-fallback-system)
        log "Setting up: File fallback - system config with flathub enabled"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        mkdir -p "$FP_BIN/var/lib/flatpak/repo"
        write_config "$FP_BIN/var/lib/flatpak/repo/config" '    [remote "flathub"]' 'url=https://dl.flathub.org/repo/' 'gpg-verify=true'
        export _FLATHUB_SYSTEM_CONFIG="$FP_BIN/var/lib/flatpak/repo/config"
        export _FLATHUB_USER_CONFIG="$(mktemp -d)/none-user"
        export FLATPAK_TEST_MODE=1
        export _FLATHUB_ALLOW_TEST_OVERRIDES=1
        export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$FP_BIN"
        PATH="/nonexistent-bin-dir"
        export PATH

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 0 ]] || fail "flathub_enabled should be true"
        [[ "$FLATHUB_STATE" == "enabled" ]] || fail "FLATHUB_STATE=enabled expected"
        [[ "$FLATHUB_SCOPE" == "system" ]] || fail "FLATHUB_SCOPE=system expected"
        log "PASS: file-fallback-system"
        ;;

    file-fallback-user)
        log "Setting up: File fallback - user config with flathub enabled"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        mkdir -p "$FP_BIN/home/user/.local/share/flatpak/repo"
        write_config "$FP_BIN/home/user/.local/share/flatpak/repo/config" '    [remote "flathub"]' 'url=https://dl.flathub.org/repo/'
        export _FLATHUB_SYSTEM_CONFIG="$(mktemp -d)/none-system"
        export _FLATHUB_USER_CONFIG="$FP_BIN/home/user/.local/share/flatpak/repo/config"
        export FLATPAK_TEST_MODE=1
        export _FLATHUB_ALLOW_TEST_OVERRIDES=1
        export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$FP_BIN"
        PATH="/nonexistent-bin-dir"
        export PATH

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 0 ]] || fail "flathub_enabled should be true"
        [[ "$FLATHUB_STATE" == "enabled" ]] || fail "FLATHUB_STATE=enabled expected"
        [[ "$FLATHUB_SCOPE" == "user" ]] || fail "FLATHUB_SCOPE=user expected"
        log "PASS: file-fallback-user"
        ;;

    file-fallback-both)
        log "Setting up: File fallback - both configs with flathub enabled"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        mkdir -p "$FP_BIN/var/lib/flatpak/repo"
        mkdir -p "$FP_BIN/home/user/.local/share/flatpak/repo"
        write_config "$FP_BIN/var/lib/flatpak/repo/config" '    [remote "flathub"]' 'url=https://dl.flathub.org/repo/'
        write_config "$FP_BIN/home/user/.local/share/flatpak/repo/config" '    [remote "flathub"]' 'url=https://dl.flathub.org/repo/'
        export _FLATHUB_SYSTEM_CONFIG="$FP_BIN/var/lib/flatpak/repo/config"
        export _FLATHUB_USER_CONFIG="$FP_BIN/home/user/.local/share/flatpak/repo/config"
        export FLATPAK_TEST_MODE=1
        export _FLATHUB_ALLOW_TEST_OVERRIDES=1
        export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$FP_BIN"
        PATH="/nonexistent-bin-dir"
        export PATH

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 0 ]] || fail "flathub_enabled should be true"
        [[ "$FLATHUB_STATE" == "enabled" ]] || fail "FLATHUB_STATE=enabled expected"
        [[ "$FLATHUB_SCOPE" == "both" ]] || fail "FLATHUB_SCOPE=both expected"
        log "PASS: file-fallback-both"
        ;;

    config-disabled)
        log "Setting up: Config has enabled=false"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        mkdir -p "$FP_BIN/var/lib/flatpak/repo"
        write_config "$FP_BIN/var/lib/flatpak/repo/config" '    [remote "flathub"]' 'enabled=false' 'url=https://dl.flathub.org/repo/'
        export _FLATHUB_SYSTEM_CONFIG="$FP_BIN/var/lib/flatpak/repo/config"
        export _FLATHUB_USER_CONFIG="$(mktemp -d)/none-user"
        export FLATPAK_TEST_MODE=1
        export _FLATHUB_ALLOW_TEST_OVERRIDES=1
        export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$FP_BIN"
        PATH="/nonexistent-bin-dir"
        export PATH

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 1 ]] || fail "flathub_enabled should be false"
        [[ "$FLATHUB_STATE" == "disabled" ]] || fail "FLATHUB_STATE=disabled expected"
        log "PASS: config-disabled"
        ;;

    reachability-probe-enabled)
        log "Setting up: Reachability probe - remote reachable"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export RL_SYSTEM="flathub"
        export RL_USER=""
        export REMOTE_INFO_EXIT=0
        export FLATPAK_TEST_MODE=1
        export FLATHUB_PROBE_REACHABILITY=1
        export PATH="$FP_BIN:$PATH"

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 0 ]] || fail "flathub_enabled should be true"
        [[ "$FLATHUB_REACHABLE" == "1" ]] || fail "FLATHUB_REACHABLE=1 expected"
        [[ "$FLATHUB_STATE" == "enabled" ]] || fail "FLATHUB_STATE=enabled expected"
        if flathub_reachable; then rc=0; else rc=1; fi
        [[ "$rc" -eq 0 ]] || fail "flathub_reachable should be true"
        log "PASS: reachability-probe-enabled"
        ;;

    reachability-probe-unreachable)
        log "Setting up: Reachability probe - remote unreachable"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export RL_SYSTEM="flathub"
        export RL_USER=""
        export REMOTE_INFO_EXIT=1
        export FLATPAK_TEST_MODE=1
        export FLATHUB_PROBE_REACHABILITY=1
        export PATH="$FP_BIN:$PATH"

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 0 ]] || fail "flathub_enabled should be true"
        [[ "$FLATHUB_REACHABLE" == "0" ]] || fail "FLATHUB_REACHABLE=0 expected"
        [[ "$FLATHUB_STATE" == "unreachable" ]] || fail "FLATHUB_STATE=unreachable expected"
        if flathub_reachable; then rc=0; else rc=1; fi
        [[ "$rc" -eq 1 ]] || fail "flathub_reachable should be false"
        log "PASS: reachability-probe-unreachable"
        ;;

    partial-failure-system)
        log "Setting up: Partial failure - system scope fails, user works (flathub enabled in user)"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export FAIL_SYSTEM=1
        export RL_USER="flathub"
        export RL_SYSTEM=""
        export FLATPAK_TEST_MODE=1
        export PATH="$FP_BIN:$PATH"

        flathub_detect || true
        [[ "$FLATHUB_STATE" == "enabled" ]] || fail "FLATHUB_STATE=enabled expected (user scope has flathub)"
        log "PASS: partial-failure-system"
        ;;

    strict-mode-caller)
        log "Testing: Safe inside strict-mode caller"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export RL_SYSTEM="flathub"
        export RL_USER=""
        export FLATPAK_TEST_MODE=1
        export PATH="$FP_BIN:$PATH"

        output=$(bash -c 'set -euo pipefail; PATH="'"$FP_BIN"':$PATH"; . '"$LIB_PATH"'; flathub_enabled; printf "ok:%s:%s" "$FLATHUB_STATE" "$FLATHUB_SCOPE"')
        [[ "$output" == "ok:enabled:system" ]] || fail "Strict mode test failed: $output"
        log "PASS: strict-mode-caller"
        ;;

    custom-installation)
        log "Setting up: Custom installation (NixOS-like) with flathub enabled"
        FP_BIN="$(mktemp -d)"
        setup_fake_flatpak "$FP_BIN"
        export RL_SYSTEM="flathub"
        export RL_USER=""
        export FLATPAK_TEST_MODE=1
        export PATH="$FP_BIN:$PATH"

        if flathub_enabled; then rc=0; else rc=1; fi
        [[ "$rc" -eq 0 ]] || fail "flathub_enabled should be true"
        [[ "$FLATHUB_STATE" == "enabled" ]] || fail "FLATHUB_STATE=enabled expected"
        [[ "$FLATHUB_SCOPE" == "system" ]] || fail "FLATHUB_SCOPE=system expected"
        log "PASS: custom-installation"
        ;;

    *)
        fail "Unknown scenario: $SCENARIO"
        ;;
esac

log "All assertions passed for scenario: $SCENARIO"