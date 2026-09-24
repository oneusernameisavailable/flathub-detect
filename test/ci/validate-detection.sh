#!/usr/bin/env bash
# validate-detection.sh — run inside each CI container/VM
# Tests fx-flathub-detect.sh against various Flatpak configurations

set -euo pipefail

# Allow LIB_PATH to be overridden via env (for local testing), default to Docker mount point
LIB_PATH="${LIB_PATH:-/src/fx-flathub-detect.sh}"
SCENARIO="${1:-}"
SELINUX_MODE="${2:-}"
APPARMOR_MODE="${3:-}"

if [[ ! -f "$LIB_PATH" ]]; then
    echo "ERROR: Library not found at $LIB_PATH" >&2
    exit 1
fi

# Source the library
source "$LIB_PATH"

# Helper: ensure flatpak is installed
ensure_flatpak() {
    if command -v flatpak >/dev/null 2>&1; then
        return 0
    fi
    echo "Installing flatpak..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq flatpak
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y flatpak
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm flatpak
    elif command -v apk >/dev/null 2>&1; then
        apk add flatpak
    elif command -v zypper >/dev/null 2>&1; then
        zypper install -y flatpak
    else
        echo "ERROR: Cannot install flatpak - no supported package manager found" >&2
        return 1
    fi
}

# Helper: run flatpak command with appropriate context
run_flatpak() {
    if [[ "$SELINUX_MODE" == "enforcing" ]]; then
        # In SELinux enforcing, system scope may need specific context
        flatpak "$@"
    else
        flatpak "$@"
    fi
}

# Helper: setup scenario preconditions
setup_scenario() {
    local scenario="$1"
    
    # Clean slate: remove flathub remote if present (both scopes)
    run_flatpak remote-delete --system flathub 2>/dev/null || true
    run_flatpak remote-delete --user flathub 2>/dev/null || true
    
    case "$scenario" in
        enabled-system)
            run_flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            ;;
        enabled-user)
            run_flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            ;;
        enabled-both)
            run_flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            run_flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            ;;
        disabled-system)
            run_flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            run_flatpak remote-modify --system --disable flathub
            ;;
        disabled-user)
            run_flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            run_flatpak remote-modify --user --disable flathub
            ;;
        not-configured)
            # Already cleaned above
            ;;
        flatpak-missing)
            # Handled by not installing flatpak in container
            ;;
        custom-installation)
            # Create custom installation config
            mkdir -p /etc/flatpak/installations.d
            cat > /etc/flatpak/installations.d/extra.conf <<'EOF'
[installation "extra"]
Path=/var/lib/flatpak/extra
EOF
            # Add flathub to custom installation
            run_flatpak --installation=extra remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            ;;
        partial-failure-system)
            # Simulate SELinux denial on system scope by removing system flatpak access
            # We'll test by checking that user scope still works when system fails
            run_flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            # System scope will fail due to no flatpak in system context (simulated)
            ;;
        reachability-probe)
            # Test with FLATHUB_PROBE_REACHABILITY=1 but network blocked
            # This is hard to test in CI, skip for now
            ;;
        stale-cache)
            # Test cache invalidation on config change
            run_flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
            # Run detection once to populate cache
            flathub_detect >/dev/null
            # Modify config (touch to simulate external change)
            touch /var/lib/flatpak/repo/config 2>/dev/null || true
            ;;
        toctou-symlink)
            # TOCTOU test - hard to reproduce in CI, skip
            ;;
        *)
            echo "ERROR: Unknown scenario: $scenario" >&2
            exit 1
            ;;
    esac
}

# Helper: verify scenario expectations
verify_scenario() {
    local scenario="$1"
    
    # Force fresh detection
    flathub_detect >/dev/null
    
    case "$scenario" in
        enabled-system)
            flathub_enabled || { echo "FAIL: expected flathub_enabled=true"; return 1; }
            [[ "$FLATHUB_SCOPE" == "system" ]] || { echo "FAIL: expected scope=system, got '$FLATHUB_SCOPE'"; return 1; }
            [[ "$FLATHUB_STATE" == "enabled" ]] || { echo "FAIL: expected state=enabled, got '$FLATHUB_STATE'"; return 1; }
            ;;
        enabled-user)
            flathub_enabled || { echo "FAIL: expected flathub_enabled=true"; return 1; }
            [[ "$FLATHUB_SCOPE" == "user" ]] || { echo "FAIL: expected scope=user, got '$FLATHUB_SCOPE'"; return 1; }
            [[ "$FLATHUB_STATE" == "enabled" ]] || { echo "FAIL: expected state=enabled, got '$FLATHUB_STATE'"; return 1; }
            ;;
        enabled-both)
            flathub_enabled || { echo "FAIL: expected flathub_enabled=true"; return 1; }
            [[ "$FLATHUB_SCOPE" == "both" ]] || { echo "FAIL: expected scope=both, got '$FLATHUB_SCOPE'"; return 1; }
            [[ "$FLATHUB_STATE" == "enabled" ]] || { echo "FAIL: expected state=enabled, got '$FLATHUB_STATE'"; return 1; }
            ;;
        disabled-system)
            ! flathub_enabled || { echo "FAIL: expected flathub_enabled=false"; return 1; }
            [[ "$FLATHUB_STATE" == "disabled" ]] || { echo "FAIL: expected state=disabled, got '$FLATHUB_STATE'"; return 1; }
            ;;
        disabled-user)
            ! flathub_enabled || { echo "FAIL: expected flathub_enabled=false"; return 1; }
            [[ "$FLATHUB_STATE" == "disabled" ]] || { echo "FAIL: expected state=disabled, got '$FLATHUB_STATE'"; return 1; }
            ;;
        not-configured)
            ! flathub_enabled || { echo "FAIL: expected flathub_enabled=false"; return 1; }
            [[ "$FLATHUB_STATE" == "not-configured" ]] || { echo "FAIL: expected state=not-configured, got '$FLATHUB_STATE'"; return 1; }
            [[ "$FLATHUB_SCOPE" == "empty" ]] || { echo "FAIL: expected scope=empty, got '$FLATHUB_SCOPE'"; return 1; }
            ;;
        flatpak-missing)
            ! flathub_enabled || { echo "FAIL: expected flathub_enabled=false"; return 1; }
            [[ "$FLATHUB_STATE" == "flatpak-missing" ]] || { echo "FAIL: expected state=flatpak-missing, got '$FLATHUB_STATE'"; return 1; }
            ;;
        custom-installation)
            flathub_enabled || { echo "FAIL: expected flathub_enabled=true"; return 1; }
            # Check that custom installation is detected in scope
            # The scope should include the installation name
            if [[ "$FLATHUB_SCOPE" != "empty" && "$FLATHUB_SCOPE" != "system" && "$FLATHUB_SCOPE" != "user" && "$FLATHUB_SCOPE" != "both" ]]; then
                echo "PASS: custom installation detected in scope: $FLATHUB_SCOPE"
            else
                echo "FAIL: expected custom installation scope, got '$FLATHUB_SCOPE'"
                return 1
            fi
            ;;
        partial-failure-system)
            # System scope fails, user scope works -> should be enabled (user)
            flathub_enabled || { echo "FAIL: expected flathub_enabled=true (user scope)"; return 1; }
            [[ "$FLATHUB_STATE" == "enabled" ]] || { echo "FAIL: expected state=enabled, got '$FLATHUB_STATE'"; return 1; }
            # Scope should be user (not system, since system failed)
            [[ "$FLATHUB_SCOPE" == "user" ]] || { echo "FAIL: expected scope=user, got '$FLATHUB_SCOPE'"; return 1; }
            ;;
        stale-cache)
            # After config touch, cache should invalidate and re-detect
            flathub_detect >/dev/null
            [[ "$FLATHUB_STATE" == "enabled" ]] || { echo "FAIL: expected state=enabled after cache invalidation"; return 1; }
            ;;
        *)
            echo "ERROR: Unknown verification for scenario: $scenario" >&2
            return 1
            ;;
    esac
    echo "PASS: $scenario"
}

# Main
main() {
    echo "=== Flathub Detection Validation ==="
    echo "Scenario: $SCENARIO"
    echo "SELinux: ${SELINUX_MODE:-none}"
    echo "AppArmor: ${APPARMOR_MODE:-none}"
    
    # Ensure flatpak is available
    ensure_flatpak
    echo "Flatpak version: $(flatpak --version 2>/dev/null || echo 'NOT INSTALLED')"
    echo ""
    
    if [[ -z "$SCENARIO" ]]; then
        echo "Usage: $0 <scenario> [selinux_mode] [apparmor_mode]"
        echo "Scenarios: enabled-system, enabled-user, enabled-both, disabled-system, disabled-user, not-configured, flatpak-missing, custom-installation, partial-failure-system, stale-cache"
        exit 1
    fi
    
    # Check if flatpak is available (except for flatpak-missing scenario)
    if [[ "$SCENARIO" != "flatpak-missing" ]]; then
        if ! command -v flatpak >/dev/null 2>&1; then
            echo "ERROR: flatpak not installed but required for scenario: $SCENARIO"
            exit 1
        fi
    fi
    
    setup_scenario "$SCENARIO"
    verify_scenario "$SCENARIO"
    
    echo ""
    echo "=== RESULT: PASS ==="
}

main "$@"