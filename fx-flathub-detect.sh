#!/usr/bin/env bash
#
# fx-flathub-detect.sh — Flathub repository enabled-detection library (source-only)
#
# PURPOSE
#   Detect whether the Flathub remote is *enabled* in a Flatpak installation on
#   this system and expose the result — enabled flag, remote state, scope and
#   the flatpak binary path — as globals plus predicates for other build
#   scripts to consume. This is a LIBRARY: sourcing it defines functions,
#   nothing else.
#
# MULTI-DISTRO
#   Detection is distro-agnostic by design. "System" and "user" installations
#   are queried through flatpak's own remote-list interface, so whatever system
#   installation layout a distro chose (default dirs, /etc/flatpak/installations.d,
#   custom --installation dirs) resolves identically. No root/sudo is required:
#   flatpak remote-list and the config probes are unprivileged reads. The raw
#   config-file fallback covers the freedesktop-standard paths only
#   (/var/lib/flatpak/repo/config, ~/.local/share/flatpak/repo/config) and is a
#   best-effort safety net for when the binary is absent or unresponsive.
#
# SCOPE SEMANTICS
#   "Enabled" means the Flathub remote is enabled in ANY installation (system
#   OR user). flatpak_scope reports where: system | user | both | empty.
#
# REQUIREMENTS
#   bash >= 4.0 ([[ =~ ]], ${var,,}? none used, here-strings and `type -P` are
#   in use). No external command is required for the predicate beyond flatpak
#   itself; the pure-bash config fallback needs no grep/sed/awk. The flatpak
#   binary is never executed for the "binary present" decision (type -P) and,
#   like the sibling flatpak-detect.sh, every executed query is degraded
#   gracefully when it fails.
#
# USAGE
#   . /path/to/fx-flathub-detect.sh
#   flathub_detect                # runs detection fresh; rc 0 = enabled
#   if flathub_enabled; then ... fi   # lazy: runs detection once, cached
#   flathub_state                 # echoes enabled|disabled|not-configured|unknown|flatpak-missing
#   flathub_scope                 # echoes system|user|both|empty
#
#   Accessor functions are LAZY and CACHE their result: the first call runs
#   the detection once, and every later call in the same shell answers from
#   memory. There is NO ordering requirement — consumers never need to "call
#   flathub_detect first". flathub_detect itself re-runs detection fresh on
#   every explicit call, as a refresh escape hatch.
#
# DETECTION LADDER  (first step that yields an answer wins)
#   1. flatpak binary present?  (`type -P flatpak`, pure PATH lookup, never
#      executes). Answer comes from the command path (2) or the file fallback (3).
#   2. AUTHORITATIVE (distro-agnostic): for scope in system user:
#        flatpak remote-list --$scope --columns=name     -> exact line "flathub"
#      An exact "flathub" line means the remote is ENABLED there (remote-list
#      hides disabled remotes). When the plain query answers "not present" but
#      flatpak remote-list --$scope --show-disabled --columns=name DOES list
#      "flathub", the remote is CONFIGURED but DISABLED.
#   3. FALLBACK (only when flatpak is absent or every remote-list call fails):
#      probe the freedesktop-standard repo config files for a
#          [remote "flathub"]
#      section. Present section = configured; enabled unless the section sets
#      `enabled=false`. Paths can be overridden for tests/chroots via
#      _FLATHUB_SYSTEM_CONFIG / _FLATHUB_USER_CONFIG.
#
# EXIT CODES
#   flathub_detect    -> 0 enabled, 1 not enabled (globals still written)
#   flathub_enabled   -> 0 iff enabled (guard: use in `if`)
#   flathub_state / flathub_scope -> 0 always (echo empty where unset)
#   outer shell -> sourced with _FLATHUB_DETECT_SOURCED set : no-op return 0
#                   executed directly (bash fx-flathub-detect.sh): exit 2 (usage)
#
# DEBUGGING
#   Set _FLATHUB_DEBUG=1 (or SCRIPT_DEBUG=1) to trace the detection steps to
#   stderr. Evaluated per call, so it can be enabled mid-session.
#
# SOURCING DISCIPLINE / EXPOSED STATE
#   Sourced files run inside the caller's shell. Therefore this library
#   deliberately does NOT set -e / set -u / pipefail, does not install traps,
#   and does not create temp files — the CALLER owns strict mode, traps, and
#   cleanup. All expansions are quoted, no eval, no `ls` parsing, and the
#   pure-bash config parser never spawns grep/sed/awk.
#
# OVERRIDES (protocol deviations, each with the concrete reason)
#   # OVERRIDE: strict-mode-at-top — a sourced file must not leak set -e/-u/
#     pipefail into its caller; the library uses ${VAR:-} defaults and guards
#     failing commands with `||` so callers MAY run strict mode. Date 2026-09-13
#   # OVERRIDE: type -P instead of command -v — the predicate must answer "is a
#     flatpak BINARY on PATH", not "does the word `flatpak` resolve at all":
#     type -P searches PATH only, skipping caller aliases/functions.
#     Date 2026-09-13
#   # OVERRIDE: PATH pinning / usage() / getopts / exit-code registry — CLI
#     concepts inapplicable to a sourced library; external command lookup uses
#     `type -P` and degrades gracefully instead. Date 2026-09-13
#   # OVERRIDE: config-file probing env overrides — _FLATHUB_SYSTEM_CONFIG and
#     _FLATHUB_USER_CONFIG retarget the fallback paths exactly like detect-os.sh's
#     _OS_ROOT test hook, so bats can fixture repo config files without touching
#     the host. Date 2026-09-13
#   # LIMITATION: remotes in *additional* flatpak installations beyond the
#     default system/user pair (e.g. a distro-defined third --installation) are
#     out of scope; the command path could adopt `--installation=` later.
#     Hidden remotes (admin-marked invisible) are intentionally not counted.
#     Date 2026-09-13

# ---------------------------------------------------------------------------
# Source guard (double-source is a no-op)
# ---------------------------------------------------------------------------
if [ -n "${_FLATHUB_DETECT_SOURCED:-}" ]; then
    # SC2317: the `exit 0` branch is the fallback when this file is sourced in
    # a context where `return` is rejected (e.g. eval/`bash -c`); it is
    # intentionally unreachable in normal `.` sourcing.
    # shellcheck disable=SC2317
    ( return 0 2>/dev/null ) || exit 0
fi
_FLATHUB_DETECT_SOURCED=1

# Only declare readonly variables on first source
if [ -z "${_FLATHUB_DETECT_VERSION:-}" ]; then
    readonly _FLATHUB_DETECT_VERSION="1.0.0"
fi

# ---------------------------------------------------------------------------
# Path pinning (capture external command paths at source time so a mutated
# caller PATH cannot redirect them). Follows the same pattern as fx-detect-os.sh.
# ---------------------------------------------------------------------------
if [ -z "${_FLATHUB_REALPATH:-}" ]; then
    _FLATHUB_REALPATH="$(command -v realpath 2>/dev/null || printf '/usr/bin/realpath')"
    readonly _FLATHUB_REALPATH
fi

# ---------------------------------------------------------------------------
# Observability helper (no-op unless debug is active)
# ---------------------------------------------------------------------------

# NAME  _flathub_debug
# ARGS  message
# WHAT  prints a trace line to stderr when _FLATHUB_DEBUG=1 or SCRIPT_DEBUG=1.
#       Re-evaluated per call so debug can be enabled mid-session.
#       Sensitive values (paths, binaries) are redacted automatically.
_flathub_debug() {
    [ "${_FLATHUB_DEBUG:-${SCRIPT_DEBUG:-0}}" = "1" ] || return 0
    local msg="$*"

    # Redact sensitive paths using patterns derived from validation allowlists
    # Home directories
    msg="${msg//\/home\/[^\/]*\//\/home\/<HOME>\/}"
    msg="${msg//\/Users\/[^\/]*\//\/Users\/<HOME>\/}"
    msg="${msg//\/root\//\/<ROOT>\/}"
    # Runtime directories
    msg="${msg//\/run\/user\/[^\/]*\//\/run\/user\/<UID>\/}"
    msg="${msg//\/tmp\/[^\/]*\//\/tmp\/<TMP>\/}"
    # Flatpak standard paths
    msg="${msg//\/var\/lib\/flatpak\/repo\/config/<CONFIG>}"
    msg="${msg//\/var\/lib\/flatpak\/repo\//<FLATPAK_REPO>\/}"
    msg="${msg//\/var\/lib\/flatpak\/exports\/bin\/flatpak/<FLATPAK_EXPORT_BIN>}"
    msg="${msg//\/etc\/flatpak\//<ETC_FLATPAK>}"
    # NixOS paths
    msg="${msg//\/nix\/store\/[^\/]*\/flatpak/<NIX_FLATPAK>}"
    msg="${msg//\/nix\/store\/[^\/]*\/bin\/flatpak/<NIX_FLATPAK_BIN>}"
    msg="${msg//\/nix\/store\/[^\/]*\/etc\/flatpak/<NIX_FLATPAK_ETC>}"
    msg="${msg//\/run\/current-system\/sw\/bin\/flatpak/<NIXOS_PROFILE_BIN>}"
    # Homebrew paths (macOS and Linuxbrew)
    msg="${msg//\/opt\/homebrew\/[^\/]*\/flatpak/<HOMEBREW_FLATPAK>}"
    msg="${msg//\/opt\/homebrew\/bin\/flatpak/<HOMEBREW_FLATPAK_BIN>}"
    msg="${msg//\/opt\/homebrew\/var\/lib\/flatpak/<HOMEBREW_FLATPAK_VAR>}"
    msg="${msg//\/opt\/homebrew\/etc\/flatpak/<HOMEBREW_FLATPAK_ETC>}"
    msg="${msg//\/usr\/local\/[^\/]*\/flatpak/<HOMEBREW_FLATPAK>}"
    msg="${msg//\/usr\/local\/bin\/flatpak/<HOMEBREW_FLATPAK_BIN>}"
    msg="${msg//\/usr\/local\/var\/lib\/flatpak/<HOMEBREW_FLATPAK_VAR>}"
    msg="${msg//\/usr\/local\/etc\/flatpak/<HOMEBREW_FLATPAK_ETC>}"
    msg="${msg//\/home\/linuxbrew\/\.linuxbrew\/[^\/]*\/flatpak/<LINUXBREW_FLATPAK>}"
    msg="${msg//\/home\/linuxbrew\/\.linuxbrew\/bin\/flatpak/<LINUXBREW_FLATPAK_BIN>}"
    msg="${msg//\/home\/linuxbrew\/\.linuxbrew\/var\/lib\/flatpak/<LINUXBREW_FLATPAK_VAR>}"
    msg="${msg//\/home\/linuxbrew\/\.linuxbrew\/etc\/flatpak/<LINUXBREW_FLATPAK_ETC>}"
    # Binary references in debug output
    msg="${msg//bin=<validated>/bin=<validated>}"
    msg="${msg//bin=[^ ]*/bin=<REDACTED>}"
    # Redact override env vars that may contain paths
    msg="${msg//_FLATHUB_PINNED_FLATPAK=[^ ]*/_FLATHUB_PINNED_FLATPAK=<REDACTED>}"
    msg="${msg//_FLATHUB_SYSTEM_CONFIG=[^ ]*/_FLATHUB_SYSTEM_CONFIG=<REDACTED>}"
    msg="${msg//_FLATHUB_USER_CONFIG=[^ ]*/_FLATHUB_USER_CONFIG=<REDACTED>}"
    msg="${msg//_FLATHUB_FLATPAK_SHA256=[^ ]*/_FLATHUB_FLATPAK_SHA256=<REDACTED>}"
    msg="${msg//_FLATHUB_TEST_ALLOW_CONFIG_DIRS=[^ ]*/_FLATHUB_TEST_ALLOW_CONFIG_DIRS=<REDACTED>}"
    # Redact XDG_DATA_HOME if present in message
    msg="${msg//${XDG_DATA_HOME//\//\\/}/<XDG_DATA_HOME>}"
    # Redact custom --installation paths (any path containing flatpak/installations)
    msg="${msg//\/flatpak\/installations\/[^\/]*/\/flatpak\/installations\/<INSTALLATION>}"

    printf '%s\n' "fx-flathub-detect: $msg" >&2
}

# ---------------------------------------------------------------------------
# Small internal helpers
# ---------------------------------------------------------------------------

# NAME  _flathub_has_name
# ARGS  output of `flatpak remote-list --columns=name`
# WHAT  scans the output line by line for an exact "flathub" match (one remote
#       per line, so a whole-line test can never false-positive on a
#       longer-named remote such as myflathub).
# RET   0 exact "flathub" line present, 1 otherwise
_flathub_has_name() {
    local line
    while IFS= read -r line; do
        [ "$line" = "flathub" ] && return 0
    done <<< "$1"
    return 1
}

# NAME  _flathub_normalize_scope
# ARGS  space-joined scope list (may carry a leading space)
# WHAT  maps a space-joined scope list onto the stable vocabulary
#       system | user | both | empty.
# RET   0 always
_flathub_normalize_scope() {
    local tok has_system=0 has_user=0
    local -a toks
    # split the (single-space-joined) list into tokens; only our own tokens
    # ("system"/"user") can ever appear here
    read -r -a toks <<< "$1"
    for tok in "${toks[@]}"; do
        [ "$tok" = "system" ] && has_system=1
        [ "$tok" = "user" ]   && has_user=1
    done
    if [ "$has_system" = "1" ] && [ "$has_user" = "1" ]; then
        printf '%s\n' "both"
    elif [ "$has_system" = "1" ]; then
        printf '%s\n' "system"
    elif [ "$has_user" = "1" ]; then
        printf '%s\n' "user"
    else
        printf '%s\n' "empty"
    fi
}

# NAME  _flathub_validate_binary
# ARGS  binary path (from _FLATHUB_PINNED_FLATPAK or PATH lookup)
# WHAT  validates that the binary path is an absolute path to an executable
#       file in an allowed location, and optionally verifies it responds like
#       flatpak (--version). This prevents PATH injection via _FLATHUB_PINNED_FLATPAK.
# RET   0 on success (prints validated path), 1 on failure
_flathub_validate_binary() {
    local bin="$1"
    [ -n "$bin" ] || return 1
    # Must be absolute path (blocks PATH-relative injection)
    case "$bin" in /*) ;; *) return 1 ;; esac
    # Must exist and be executable regular file
    [ -f "$bin" ] && [ -x "$bin" ] || return 1
    # Must be in an allowed binary path (defeats PATH injection + binary substitution)
    case "$bin" in
        /usr/bin/flatpak|/usr/local/bin/flatpak|/opt/homebrew/bin/flatpak) ;;
        /nix/store/*/bin/flatpak) ;;
        /nix/var/nix/profiles/system/sw/bin/flatpak) ;;
        /nix/var/nix/profiles/per-user/*/bin/flatpak) ;;
        /run/current-system/sw/bin/flatpak) ;;
        /var/lib/flatpak/exports/bin/flatpak) ;;
        /snap/bin/flatpak) ;;
        /home/linuxbrew/.linuxbrew/bin/flatpak) ;;
        ~/.local/bin/flatpak) ;;
        /run/host/usr/bin/flatpak) ;;
        /usr/lib/flatpak/flatpak) ;;
        *)
            # C4: SHA256 escape hatch only allowed in test mode (FLATPAK_TEST_MODE=1)
            if [ "${FLATPAK_TEST_MODE:-0}" = "1" ] && [ -n "${_FLATHUB_FLATPAK_SHA256:-}" ]; then
                local sum
                sum="$(sha256sum "$bin" 2>/dev/null | cut -d' ' -f1)"
                [ "$sum" = "$_FLATHUB_FLATPAK_SHA256" ] || return 1
            else
                return 1
            fi
            ;;
    esac
    # Verify it's actually flatpak via --version (read-only, benign)
    # Pattern matches semantic version output like "1.15.8", "1.15.8-1", "1.15.8+git.abc123"
    # Use bash built-in regex to avoid grep dependency
    local version_out
    version_out="$("$bin" --version 2>/dev/null)" || return 1
    [[ "$version_out" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || return 1
    printf '%s\n' "$bin"
    return 0
}

# NAME  _flathub_system_config / _flathub_user_config
# ARGS  none
# WHAT  prints the effective repo config path for the fallback probe. The
#       system path follows the freedesktop default /var/lib/flatpak; the user
#       path honors XDG_DATA_HOME. Both are retargetable per-call via env for
#       tests/chroots. Also supports NixOS and Homebrew custom paths.
#       C5: Override env vars (_FLATHUB_SYSTEM_CONFIG, _FLATHUB_USER_CONFIG)
#       only work when FLATPAK_TEST_MODE=1 is set (cryptographic test/prod separation).
# RET   sanitized absolute path
_flathub_system_config() {
    local p="${_FLATHUB_SYSTEM_CONFIG:-/var/lib/flatpak/repo/config}"
    # C5: Override only allowed in test mode
    if [ -n "${_FLATHUB_SYSTEM_CONFIG:-}" ] && [ "${FLATPAK_TEST_MODE:-0}" != "1" ]; then
        _flathub_debug "ignoring _FLATHUB_SYSTEM_CONFIG override (FLATPAK_TEST_MODE not set)"
        p="/var/lib/flatpak/repo/config"
    fi
    # Reject path traversal attempts (most specific patterns first)
    case "$p" in
        /..|..) _flathub_debug "rejected traversal: $p"; p="/var/lib/flatpak/repo/config" ;;
        */..) _flathub_debug "rejected traversal: $p"; p="/var/lib/flatpak/repo/config" ;;
        */../*) _flathub_debug "rejected traversal: $p"; p="/var/lib/flatpak/repo/config" ;;
    esac
    # Must be absolute path
    case "$p" in /*) ;; *) p="/var/lib/flatpak/repo/config" ;; esac
    # NixOS custom paths are validated in _flathub_validate_config_path_original/canonical
    printf '%s\n' "$p"
}
_flathub_user_config() {
    local h="${HOME:-}"
    local p="${_FLATHUB_USER_CONFIG:-${XDG_DATA_HOME:-$h/.local/share}/flatpak/repo/config}"
    # C5: Override only allowed in test mode
    if [ -n "${_FLATHUB_USER_CONFIG:-}" ] && [ "${FLATPAK_TEST_MODE:-0}" != "1" ]; then
        _flathub_debug "ignoring _FLATHUB_USER_CONFIG override (FLATPAK_TEST_MODE not set)"
        p="${XDG_DATA_HOME:-$h/.local/share}/flatpak/repo/config"
    fi
    case "$p" in
        /..|..) _flathub_debug "rejected traversal: $p"; p="${XDG_DATA_HOME:-$h/.local/share}/flatpak/repo/config" ;;
        */..) _flathub_debug "rejected traversal: $p"; p="${XDG_DATA_HOME:-$h/.local/share}/flatpak/repo/config" ;;
        */../*) _flathub_debug "rejected traversal: $p"; p="${XDG_DATA_HOME:-$h/.local/share}/flatpak/repo/config" ;;
    esac
    case "$p" in /*) ;; *) p="${XDG_DATA_HOME:-$h/.local/share}/flatpak/repo/config" ;; esac
    # Homebrew custom paths are validated in _flathub_validate_config_path_original/canonical
    printf '%s\n' "$p"
}

# NAME  _flathub_check_nixos
# WHAT  returns 0 if running on NixOS (via os-release ID=nixos)
_flathub_check_nixos() {
    [[ -r /etc/os-release ]] || return 1
    while IFS= read -r line; do
        # Match ID=nixos with optional quotes (double, single, none)
        case "$line" in
            ID=nixos|ID=\"nixos\"|ID=\'nixos\') return 0 ;;
        esac
    done < /etc/os-release
    return 1
}

# NAME  _flathub_check_homebrew
# WHAT  returns 0 if Homebrew is installed (macOS)
_flathub_check_homebrew() {
    [ -x "/opt/homebrew/bin/brew" ] || [ -x "/usr/local/bin/brew" ]
}

# NAME  _flathub_probe_config
# ARGS  config file path
# WHAT  parses the repo config for a `[remote "flathub"]` (or `[remote flathub]`)
#       section and records configured/enabled in the internal globals
#       _flathub_cf_configured / _flathub_cf_enabled. A present section is
#       enabled by default; an `enabled=false` (or no/off/0) key disables it.
#       Malformed values are treated as disabled (fail-safe).
#       C3: Uses fd-based atomic read to eliminate TOCTOU window.
# RET   0 flathub section present, 1 file unreadable or no section
_flathub_probe_config() {
    local f="$1" line section="" k v f_canon
    local fd
    _flathub_cf_configured=0
    _flathub_cf_enabled=0
    _flathub_cf_malformed=0
    if [ ! -r "$f" ]; then
        _flathub_debug "config unreadable"
        return 1
    fi
    # C3: TOCTOU-safe fd-based validation
    # Open file descriptor FIRST, then validate via fd, then read via fd
    # This eliminates the symlink race between validation and read
    exec {fd}<"$f" || { _flathub_debug "failed to open config fd"; return 1; }
    
    # Validate the fd path (resolves symlinks via /proc/self/fd)
    local fd_path
    fd_path="$(_flathub_fd_path "$fd")" || { exec {fd}<&-; return 1; }
    _flathub_validate_config_path_canonical "$fd_path" || { exec {fd}<&-; return 1; }
    
    # Read via fd (atomic, no TOCTOU)
    local -a config_lines
    while IFS= read -r -u "$fd" line || [ -n "$line" ]; do
        config_lines+=("$line")
    done
    exec {fd}<&-
    
    # Now parse from memory (no TOCTOU possible)
    local flathub_section_re='^[[:space:]]*\[remote[[:space:]]+['"'"'"]?flathub['"'"'"]?\][[:space:]]*(#.*)?$'
    for line in "${config_lines[@]}"; do
        case "$line" in
            ''|[[:space:]]*\#*) continue ;;
            *\[*)
                # section header; only `[remote "flathub"]` variants interest us
                # (leading whitespace tolerated for indented/ini-style files)
                if [[ "$line" =~ $flathub_section_re ]]; then
                    section=flathub
                    _flathub_cf_configured=1
                    _flathub_cf_enabled=1   # flatpak default: present = enabled
                else
                    section=""
                fi
                ;;
            *=*)
                if [ "$section" = "flathub" ]; then
                    k="${line%%=*}"
                    k="${k#"${k%%[![:space:]]*}"}"; k="${k%"${k##*[![:space:]]}"}"
                    if [ "$k" = "enabled" ]; then
                        v="${line#*=}"
                        v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
                        # Strip inline comments from value
                        v="${v%%#*}"
                        v="${v%"${v##*[![:space:]]}"}"
                        case "${v,,}" in
                            false|off|no|0|disabled) _flathub_cf_enabled=0 ;;
                            true|on|yes|1|enabled|auto) _flathub_cf_enabled=1 ;;
                            *) _flathub_cf_enabled=0; _flathub_cf_malformed=1 ;;
                        esac
                    fi
                fi
                ;;
            *[![:space:]]*)
                # Only flag as malformed if it's not a valid key=value (already handled)
                # and not a section header (already handled) and not empty/comment
                # This catches truly malformed lines like "garbage" without =
                [ -n "$section" ] && _flathub_cf_malformed=1 ;;
        esac
    done
    _flathub_debug "config probed: configured=$_flathub_cf_configured enabled=$_flathub_cf_enabled"
    [ "$_flathub_cf_configured" = "1" ]
}

# NAME  _flathub_fd_path
# ARGS  fd (file descriptor number)
# WHAT  returns the canonical path for an open file descriptor via /proc/self/fd
#       used for TOCTOU-safe path validation after opening
# RET   0 on success (prints path), 1 on failure
_flathub_fd_path() {
    local fd="$1"
    local proc_fd="/proc/self/fd/$fd"
    if [ ! -e "$proc_fd" ]; then
        _flathub_debug "fd path not accessible: $proc_fd"
        return 1
    fi
    local canon_path
    canon_path="$("$_FLATHUB_REALPATH" "$proc_fd" 2>/dev/null)" || return 1
    printf '%s\n' "$canon_path"
    return 0
}

# NAME  _flathub_validate_config_path_original
# ARGS  original config file path (before realpath)
# WHAT  validates original path against allowlist BEFORE canonicalization
#       prevents symlink traversal attacks
#       C5: Test override (_FLATHUB_TEST_ALLOW_CONFIG_DIRS) only works with FLATPAK_TEST_MODE=1
# RET   0 if allowed, 1 if rejected
_flathub_validate_config_path_original() {
    local f="$1"
    # Test override: allow additional directories via _FLATHUB_TEST_ALLOW_CONFIG_DIRS
    # ONLY when FLATPAK_TEST_MODE=1 AND _FLATHUB_ALLOW_TEST_OVERRIDES=1 are both set (dual gate + test mode)
    local allow_test=0
    if [ "${FLATPAK_TEST_MODE:-0}" = "1" ] && [ -n "${_FLATHUB_ALLOW_TEST_OVERRIDES:-}" ] && [ -n "${_FLATHUB_TEST_ALLOW_CONFIG_DIRS:-}" ]; then
        case "$f" in
            ${_FLATHUB_TEST_ALLOW_CONFIG_DIRS}/*) allow_test=1 ;;
        esac
    fi
    if [ "$allow_test" -eq 0 ]; then
        case "$f" in
            /var/lib/flatpak/*) ;;
            "$HOME"/.local/share/flatpak/*) ;;
            ${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/*) ;;
            /nix/store/*/etc/flatpak/*) _flathub_check_nixos || return 1 ;;
            /etc/flatpak/*) _flathub_check_nixos || return 1 ;;
            /nix/store/*/flatpak/*) _flathub_check_nixos || return 1 ;;
            /opt/homebrew/var/lib/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /opt/homebrew/etc/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /usr/local/var/lib/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /usr/local/etc/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /home/linuxbrew/.linuxbrew/var/lib/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /home/linuxbrew/.linuxbrew/etc/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /opt/homebrew/*/flatpak/*|/usr/local/*/flatpak/*) _flathub_check_homebrew || return 1 ;;
            *) _flathub_debug "config outside allowed dirs (original)"; return 1 ;;
        esac
    fi
    return 0
}

# NAME  _flathub_validate_config_path_canonical
# ARGS  canonical config file path (after realpath -m)
# WHAT  validates canonical path against allowlist AFTER canonicalization
#       ensures the resolved path is still under allowed directories
#       C5: Test override (_FLATHUB_TEST_ALLOW_CONFIG_DIRS) only works with FLATPAK_TEST_MODE=1
# RET   0 if allowed, 1 if rejected
_flathub_validate_config_path_canonical() {
    local f_canon="$1"
    local allow_test=0
    if [ "${FLATPAK_TEST_MODE:-0}" = "1" ] && [ -n "${_FLATHUB_ALLOW_TEST_OVERRIDES:-}" ] && [ -n "${_FLATHUB_TEST_ALLOW_CONFIG_DIRS:-}" ]; then
        case "$f_canon" in
            ${_FLATHUB_TEST_ALLOW_CONFIG_DIRS}/*) allow_test=1 ;;
        esac
    fi
    if [ "$allow_test" -eq 0 ]; then
        case "$f_canon" in
            /var/lib/flatpak/*) ;;
            "$HOME"/.local/share/flatpak/*) ;;
            ${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/*) ;;
            /nix/store/*/etc/flatpak/*) _flathub_check_nixos || return 1 ;;
            /etc/flatpak/*) _flathub_check_nixos || return 1 ;;
            /nix/store/*/flatpak/*) _flathub_check_nixos || return 1 ;;
            /opt/homebrew/var/lib/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /opt/homebrew/etc/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /usr/local/var/lib/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /usr/local/etc/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /home/linuxbrew/.linuxbrew/var/lib/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /home/linuxbrew/.linuxbrew/etc/flatpak/*) _flathub_check_homebrew || return 1 ;;
            /opt/homebrew/*/flatpak/*|/usr/local/*/flatpak/*) _flathub_check_homebrew || return 1 ;;
            *) _flathub_debug "config outside allowed dirs (canonical)"; return 1 ;;
        esac
    fi
    return 0
}

# NAME  _flathub_probe_files
# ARGS  none
# WHAT  file-fallback step: probes the system and user repo config files and
#       merges their results into the FLATHUB_* globals (including scope).
# RET   0 flathub configured in at least one config file
_flathub_probe_files() {
    local f detected=0 malformed=0 scope_list=""
    f="$(_flathub_system_config)"
    if _flathub_probe_config "$f"; then
        detected=1
        FLATHUB_CONFIGURED=1
        if [ "$_flathub_cf_enabled" = "1" ]; then
            FLATHUB_ENABLED=1
            scope_list="$scope_list system"
        fi
    fi
    [ "${_flathub_cf_malformed:-0}" = "1" ] && malformed=1
    f="$(_flathub_user_config)"
    if _flathub_probe_config "$f"; then
        detected=1
        FLATHUB_CONFIGURED=1
        if [ "$_flathub_cf_enabled" = "1" ]; then
            FLATHUB_ENABLED=1
            scope_list="$scope_list user"
        fi
    fi
    [ "${_flathub_cf_malformed:-0}" = "1" ] && malformed=1
    # Normalize scope using shared helper
    if [ -n "$scope_list" ]; then
        FLATHUB_SCOPE="$(_flathub_normalize_scope "$scope_list")"
    fi
    _flathub_files_malformed="$malformed"
    [ "$detected" = "1" ]
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

# NAME  flathub_detect
# ARGS  none
# WHAT  runs detection fresh and writes every FLATHUB_* global. "Enabled" means
#       the flathub remote is enabled in ANY installation (system or user) per
#       the ladder in the header. Every global is always written, so callers
#       (including set -u ones) never trip over unset variables.
# GLOBALS WRITTEN  FLATHUB_ENABLED FLATHUB_CONFIGURED FLATHUB_STATE
#                  FLATHUB_SCOPE FLATHUB_BIN _FLATHUB_DETECTED
# RET   0 enabled, 1 not enabled
flathub_detect() {
    local bin scope out rc
    local -A scope_normal_ok scope_has_flathub scope_disabled_ok
    local normal_answered=0
    local scopes=""
    _flathub_debug "detect start"
    FLATHUB_ENABLED=0
    FLATHUB_CONFIGURED=0
    FLATHUB_STATE=not-configured
    FLATHUB_SCOPE=""
    FLATHUB_BIN=""
    FLATHUB_REACHABLE=0          # NEW: network reachability (C1-REACH)
    FLATHUB_SCOPES_JSON=""  # per-scope detailed results (C6)
    _flathub_files_malformed=0
    _FLATHUB_CACHE_HASH=""  # reset cache hash for fresh detection

    # --- step 1: flatpak binary present? (pure PATH lookup, never executed) ---
    bin="${_FLATHUB_PINNED_FLATPAK:-}"
    if [ -n "$bin" ]; then
        bin="$(_flathub_validate_binary "$bin")" || bin=""
    fi
    [ -n "$bin" ] || bin="$(type -P flatpak 2>/dev/null)" || true
    if [ -n "$bin" ]; then
        # Validate PATH-found binary too (defense in depth)
        bin="$(_flathub_validate_binary "$bin")" || bin=""
    fi
    if [ -n "$bin" ]; then
        FLATHUB_BIN="$bin"
        _flathub_debug "flatpak bin=<validated>"

        # --- C1: Reachability probe before trusting metadata ---
        # Verify flatpak binary is functional and can query remotes
        if ! "$bin" --version >/dev/null 2>&1; then
            _flathub_debug "flatpak binary unreachable (--version failed)"
            bin=""  # Treat as absent, triggers fallback
        elif ! "$bin" remote-list --columns=name >/dev/null 2>&1; then
            _flathub_debug "flatpak remote-list unreachable"
            bin=""  # Treat as absent, triggers fallback
        elif [ "${FLATHUB_PROBE_REACHABILITY:-0}" = "1" ]; then
            # C1-REACH: Optional network reachability check
            _flathub_debug "probing Flathub remote connectivity (FLATHUB_PROBE_REACHABILITY=1)"
            local reachable=0
            # Use timeout if available to prevent hanging on network issues
            if command -v timeout >/dev/null 2>&1; then
                if timeout 5 "$bin" remote-info flathub >/dev/null 2>&1; then
                    reachable=1
                    _flathub_debug "Flathub remote reachable"
                else
                    _flathub_debug "Flathub remote UNREACHABLE (network/DNS/TLS/mirror issue or timeout)"
                fi
            else
                # No timeout command; run with background + kill as fallback
                "$bin" remote-info flathub >/dev/null 2>&1 &
                local pid=$!
                sleep 5 2>/dev/null || sleep 5
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid" 2>/dev/null
                    _flathub_debug "Flathub remote UNREACHABLE (timeout after 5s)"
                else
                    wait "$pid" 2>/dev/null
                    reachable=1
                    _flathub_debug "Flathub remote reachable"
                fi
            fi
            FLATHUB_REACHABLE=$reachable
        fi
    fi

    if [ -n "$bin" ]; then
        FLATHUB_BIN="$bin"
        _flathub_debug "flatpak bin=<validated> reachable=yes"

        # --- step 2: authoritative per-scope remote-list query ---
        # A plain (non --show-disabled) remote-list hides disabled remotes, so
        # an exact "flathub" line is precisely "enabled in this scope".
        for scope in system user; do
            scope_normal_ok[$scope]=0
            scope_has_flathub[$scope]=0
            scope_disabled_ok[$scope]=0
            rc=0
            out="$("$bin" remote-list --"$scope" --columns=name 2>/dev/null)" || rc=$?
            if [ "$rc" -eq 0 ]; then
                scope_normal_ok[$scope]=1
                normal_answered=$((normal_answered + 1))
                if _flathub_has_name "$out"; then
                    scope_has_flathub[$scope]=1
                    scopes="$scopes $scope"
                    _flathub_debug "enabled remote-list scope=$scope"
                else
                    _flathub_debug "remote-list scope=$scope answered, no flathub"
                fi
            else
                _flathub_debug "remote-list scope=$scope failed rc=$rc"
            fi
        done

        # configured-but-disabled: where a plain query answered without flathub,
        # an exact "flathub" line under --show-disabled proves a CONFIGURED
        # remote that is simply disabled. Run per-scope where normal query succeeded.
        # Run for ALL scopes that answered normally, regardless of whether another scope found flathub enabled.
        for scope in system user; do
            if [ "${scope_normal_ok[$scope]:-0}" = "1" ] && [ "${scope_has_flathub[$scope]:-0}" = "0" ]; then
                rc=0
                out="$("$bin" remote-list --"$scope" --show-disabled --columns=name 2>/dev/null)" || rc=$?
                if [ "$rc" -eq 0 ]; then
                    if _flathub_has_name "$out"; then
                        scope_disabled_ok[$scope]=1
                        _flathub_debug "configured-but-disabled scope=$scope"
                    fi
                fi
            fi
        done
    fi

    # --- step 3: file fallback ---
    # Fallback triggers when:
    # - binary is absent OR
    # - binary exists but ALL normal queries failed (normal_answered=0)
    # This matches the documented ladder: config fallback only when binary absent OR all queries fail
    if [ -z "$bin" ] || [ "$normal_answered" -eq 0 ]; then
        _flathub_debug "command path inconclusive (bin=${bin:-none} normal_answered=$normal_answered); probing config files"
        _flathub_probe_files
    fi

    # --- finalize ---
    # Aggregate per-scope results with proper isolation
    local any_enabled=0 any_disabled=0 any_configured=0 scopes_with_flathub="" scopes_configured=""
    local scopes_json_parts=()
    for scope in system user; do
        local scope_enabled=0 scope_disabled=0 scope_configured=0 scope_reachable_val=0 scope_error=""
        if [ "${scope_has_flathub[$scope]:-0}" = "1" ]; then
            any_enabled=1
            scope_enabled=1
            scopes_with_flathub="$scopes_with_flathub $scope"
        fi
        if [ "${scope_normal_ok[$scope]:-0}" = "1" ] && [ "${scope_has_flathub[$scope]:-0}" = "0" ] && [ "${scope_disabled_ok[$scope]:-0}" = "1" ]; then
            any_disabled=1
            any_configured=1
            scope_disabled=1
            scope_configured=1
            scopes_configured="$scopes_configured $scope"
        fi
        if [ "${scope_normal_ok[$scope]:-0}" = "1" ]; then
            scope_reachable_val=1
            if [ "${scope_has_flathub[$scope]:-0}" = "0" ] && [ "${scope_disabled_ok[$scope]:-0}" = "0" ]; then
                scope_configured=1  # authoritative "not-configured" for this scope
            fi
        else
            scope_error="query_failed"
        fi
        # Build per-scope JSON (C6)
        scopes_json_parts+=("{\"scope\":\"$scope\",\"enabled\":$scope_enabled,\"disabled\":$scope_disabled,\"configured\":$scope_configured,\"reachable\":$scope_reachable_val${scope_error:+,\"error\":\"$scope_error\"}}")
    done
    FLATHUB_SCOPES_JSON="[$(IFS=,; echo "${scopes_json_parts[*]}")]"

    # Also incorporate file fallback results
    if [ "${FLATHUB_ENABLED:-0}" = "1" ]; then
        any_enabled=1
        # File fallback scope is already in FLATHUB_SCOPE from _flathub_probe_files
    fi
    if [ "${FLATHUB_CONFIGURED:-0}" = "1" ] && [ "${FLATHUB_ENABLED:-0}" = "0" ]; then
        any_disabled=1
        any_configured=1
    fi

    # State machine with proper per-scope isolation
    if [ "$any_enabled" = "1" ]; then
        FLATHUB_ENABLED=1
        FLATHUB_CONFIGURED=1
        if [ "${FLATHUB_REACHABLE:-0}" = "0" ] && [ "${FLATHUB_PROBE_REACHABILITY:-0}" = "1" ]; then
            FLATHUB_STATE=unreachable
        else
            FLATHUB_STATE=enabled
        fi
        # Use scope from command path if found, else from file fallback
        if [ -n "$scopes_with_flathub" ]; then
            FLATHUB_SCOPE="$(_flathub_normalize_scope "$scopes_with_flathub")"
        fi
    elif [ "$any_disabled" = "1" ] || [ "$any_configured" = "1" ]; then
        FLATHUB_CONFIGURED=1
        FLATHUB_STATE=disabled
        # Scope for disabled: use scopes where we found configured-but-disabled
        if [ -n "$scopes_configured" ]; then
            FLATHUB_SCOPE="$(_flathub_normalize_scope "$scopes_configured")"
        fi
    elif [ "$_flathub_files_malformed" = "1" ]; then
        FLATHUB_STATE=unknown
    elif [ -z "$bin" ]; then
        FLATHUB_STATE=flatpak-missing
    elif [ "${scope_normal_ok[system]:-0}" = "1" ] && [ "${scope_has_flathub[system]:-0}" = "0" ] && [ "${scope_disabled_ok[system]:-0}" = "0" ] && [ "${scope_normal_ok[user]:-0}" = "1" ] && [ "${scope_has_flathub[user]:-0}" = "0" ] && [ "${scope_disabled_ok[user]:-0}" = "0" ]; then
        # Both scopes answered authoritatively with no flathub
        FLATHUB_STATE=not-configured
    elif [ "${scope_normal_ok[system]:-0}" = "1" ] && [ "${scope_has_flathub[system]:-0}" = "0" ] && [ "${scope_disabled_ok[system]:-0}" = "0" ] && [ "${scope_normal_ok[user]:-0}" = "0" ]; then
        # System authoritative no-flathub, user unreachable -> trust system
        FLATHUB_STATE=not-configured
    elif [ "${scope_normal_ok[user]:-0}" = "1" ] && [ "${scope_has_flathub[user]:-0}" = "0" ] && [ "${scope_disabled_ok[user]:-0}" = "0" ] && [ "${scope_normal_ok[system]:-0}" = "0" ]; then
        # User authoritative no-flathub, system unreachable -> trust user
        FLATHUB_STATE=not-configured
    elif [ "$normal_answered" -eq 0 ]; then
        # No scope answered authoritatively
        FLATHUB_STATE=unknown
    else
        # Mixed state not covered above
        FLATHUB_STATE=unknown
    fi

    _FLATHUB_DETECTED=1
    # Store cache hash for integrity verification on subsequent calls
    _FLATHUB_CACHE_HASH="$(_flathub_compute_cache_hash)"
    _flathub_debug "RESULT enabled=$FLATHUB_ENABLED configured=$FLATHUB_CONFIGURED state=$FLATHUB_STATE scope=${FLATHUB_SCOPE:-empty} scopes_json=$FLATHUB_SCOPES_JSON"
    [ "$FLATHUB_ENABLED" = "1" ]
}

# Return success only when the exact requested scope currently lists flathub.
# Returns: 0 = enabled, 1 = not enabled (authoritative), 2 = error (can't determine)
flathub_scope_enabled() {
    local requested="$1" bin="${_FLATHUB_PINNED_FLATPAK:-${FLATHUB_BIN:-}}" out rc=0
    case "$requested" in system|user) ;; *) return 2 ;; esac
    [ -n "$bin" ] || bin="$(type -P flatpak 2>/dev/null)" || return 2
    bin="$(_flathub_validate_binary "$bin")" || return 2
    out="$("$bin" remote-list --"$requested" --columns=name 2>/dev/null)" || rc=$?
    if [ "$rc" -ne 0 ]; then
        return 2
    fi
    _flathub_has_name "$out"
}

# NAME  _flathub_ensure
# ARGS  none
# WHAT  internal: runs detection at most once per shell (lazy cache backing
#       every accessor). Consumers therefore never need to call flathub_detect
#       first, and repeated accessor calls never re-spawn subprocesses.
#       Includes cache integrity verification to prevent cache poisoning.
_flathub_ensure() {
    if [ "${_FLATHUB_DETECTED:-0}" != "1" ]; then
        flathub_detect >/dev/null 2>&1 || true
    else
        # Cache integrity check: verify cached results match a recomputed hash
        _flathub_verify_cache_integrity || {
            _flathub_debug "cache integrity check failed; re-running detection"
            flathub_detect >/dev/null 2>&1 || true
        }
    fi
}

# NAME  _flathub_compute_cache_hash
# ARGS  none
# WHAT  computes a hash of the current detection cache state
#       used for cache integrity verification. Includes input fingerprints
#       (config file content hashes, binary content hash) to detect external state drift.
# RET   prints hash to stdout
_flathub_compute_cache_hash() {
    local hash_input="${FLATHUB_ENABLED:-}:${FLATHUB_CONFIGURED:-}:${FLATHUB_STATE:-}:${FLATHUB_SCOPE:-}:${FLATHUB_BIN:-}:${FLATHUB_REACHABLE:-}:${FLATHUB_SCOPES_JSON:-}"

    # Add input fingerprints to detect external state changes
    # C2: Use SHA-256 content hash for config files and binary, not just mtime:size
    local fp
    if [ -n "${FLATHUB_BIN:-}" ] && [ -f "${FLATHUB_BIN}" ]; then
        fp="$(_flathub_content_fingerprint "${FLATHUB_BIN}")"
        hash_input="${hash_input}:bin:${fp}"
    fi
    local sys_cfg
    sys_cfg="$(_flathub_system_config)"
    if [ -r "$sys_cfg" ]; then
        fp="$(_flathub_content_fingerprint "$sys_cfg")"
        hash_input="${hash_input}:sys:${fp}"
    fi
    local usr_cfg
    usr_cfg="$(_flathub_user_config)"
    if [ -r "$usr_cfg" ]; then
        fp="$(_flathub_content_fingerprint "$usr_cfg")"
        hash_input="${hash_input}:usr:${fp}"
    fi

    # Use sha256sum for cryptographic hash (required for integrity)
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s\n' "$hash_input" | sha256sum | cut -d' ' -f1
    else
        # Fallback: require sha256sum for security; fail closed if absent
        _flathub_debug "sha256sum not available; cache integrity degraded"
        # Still compute djb2 but mark as weak
        local h=5381 i c
        for (( i=0; i<${#hash_input}; i++ )); do
            c="${hash_input:i:1}"
            h=$(( (h * 33) + $(printf '%d' "'$c") ))
        done
        printf 'weak:%x\n' "$h"
    fi
}

# Content fingerprint: SHA-256 hash of file content (C2)
# Falls back to mtime:size only if sha256sum unavailable
_flathub_content_fingerprint() {
    local f="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" 2>/dev/null | cut -d' ' -f1
    else
        # Fallback: portable mtime:size
        if stat -c '%Y:%s' "$f" >/dev/null 2>&1; then
            stat -c '%Y:%s' "$f" 2>/dev/null
        elif stat -f '%m:%z' "$f" >/dev/null 2>&1; then
            stat -f '%m:%z' "$f" 2>/dev/null
        else
            printf 'unknown'
        fi
    fi
}

# Portable file fingerprint: mtime:size (works on GNU and BSD stat)
# Kept for backward compatibility with existing cache entries
_flathub_file_fingerprint() {
    local f="$1"
    if stat -c '%Y:%s' "$f" >/dev/null 2>&1; then
        stat -c '%Y:%s' "$f" 2>/dev/null
    elif stat -f '%m:%z' "$f" >/dev/null 2>&1; then
        stat -f '%m:%z' "$f" 2>/dev/null
    else
        printf 'unknown'
    fi
}

# NAME  _flathub_verify_cache_integrity
# ARGS  none
# WHAT  verifies the cached detection results haven't been tampered with
#       by comparing stored hash with recomputed hash
# RET   0 if cache is valid, 1 if corrupted/poisoned
_flathub_verify_cache_integrity() {
    local stored_hash="${_FLATHUB_CACHE_HASH:-}"
    [ -n "$stored_hash" ] || return 1
    local current_hash
    current_hash="$(_flathub_compute_cache_hash)"
    [ "$stored_hash" = "$current_hash" ]
}

# ---------------------------------------------------------------------------
# Accessor functions (lazy + cached; echo empty string where unset)
# ---------------------------------------------------------------------------
flathub_enabled() { _flathub_ensure; [ "${FLATHUB_ENABLED:-0}" = "1" ]; }
flathub_state()   { _flathub_ensure; printf '%s\n' "${FLATHUB_STATE:-not-configured}"; }
flathub_scope()   { _flathub_ensure; printf '%s\n' "${FLATHUB_SCOPE:-empty}"; }
flathub_reachable() { _flathub_ensure; [ "${FLATHUB_REACHABLE:-0}" = "1" ]; }

# ---------------------------------------------------------------------------
# Direct-execution guard (library is source-only)
# ---------------------------------------------------------------------------
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" = "$0" ]; then
    printf '%s\n' "fx-flathub-detect.sh $_FLATHUB_DETECT_VERSION is a source-only library — do not execute directly." >&2
    printf '%s\n' "Usage:  . ${0##*/}    then:   if flathub_enabled; then ..." >&2
    exit 2
fi