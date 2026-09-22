#!/usr/bin/env bats
# SC1091: `$BATS_TEST_DIRNAME/../fx-flathub-detect.sh` is a runtime-variable path;
# v0.10 cannot follow `.` sources that live inside @test blocks. The library
# file itself is linted separately, so this guard adds no coverage gap.
# shellcheck disable=SC1091
#
# fx-flathub-detect.sh integration tests.
#
# Run with:  bats test/flathub_detect.bats   (requires https://bats-core.github.io)
# Every test isolates detection behind a fixture `bin/` directory placed on a
# controlled PATH and, for the config-file fallback, env-var repository-path
# overrides — so a host-installed flatpak or a host flathub config never
# influences the outcome and no system path is ever touched.
# shellcheck disable=SC2030,SC2031,SC2123  # PATH is reassigned per @test; bats
# runs each test in its own fresh process and the PATH sandboxing IS the
# mechanism under test, so the "local to subshell" warnings are false positives.
# shellcheck disable=SC2016  # the fixture helpers write the \${RL_*}/\$* text
# literally into fake-binary scripts; those references must NOT expand here —
# they expand inside the fixture process at test runtime, which is the point.

setup() {
    export FP_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$FP_BIN"
}

lib() {
    . "$BATS_TEST_DIRNAME/../fx-flathub-detect.sh"
}

# helper: fixture `flatpak` that emulates `remote-list` from control variables.
#   RL_SYSTEM / RL_USER   : space-separated remote names for the plain (enabled)
#                           query of that scope
#   RL_SYSTEM_DISABLED /  : extra remote names shown only under --show-disabled
#   RL_USER_DISABLED        (i.e. configured-but-disabled remotes)
#   Also handles --version for binary validation.
# The fixture is quiet and argv-driven, so a host flatpak can never leak in.
_fake_flatpak() {
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'case "$1" in' \
        '  --version) printf "1.15.8\n"; exit 0 ;;' \
        'esac' \
        'scope=""; list=""' \
        'case " $* " in' \
        '  *" --system "*) scope=system ;;' \
        '  *" --user "*)   scope=user   ;;' \
        'esac' \
        'case "$scope" in' \
        '  system) list="${RL_SYSTEM:-}" ;;' \
        '  user)   list="${RL_USER:-}"   ;;' \
        'esac' \
        '[[ "$scope" == system && "${FAIL_SYSTEM:-0}" == 1 ]] && exit 7' \
        'case " $* " in' \
        '  *" --show-disabled "*)' \
        '    case "$scope" in' \
        '      system) list="$list ${RL_SYSTEM_DISABLED:-}" ;;' \
        '      user)   list="$list ${RL_USER_DISABLED:-}"   ;;' \
        '    esac ;;' \
        'esac' \
        'for n in $list; do printf "%s\n" "$n"; done' \
        > "$FP_BIN/flatpak"
    chmod +x "$FP_BIN/flatpak"
    export _FLATHUB_FLATPAK_SHA256="$(sha256sum "$FP_BIN/flatpak" | cut -d' ' -f1)"
    export FLATPAK_TEST_MODE=1
}

# helper: fixture `flatpak` that ALSO appends a line to $BATS_TEST_TMPDIR/calls
# on every invocation (proves the binary is spawned exactly N times)
_fake_flatpak_counting() {
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'case "$1" in' \
        '  --version) printf "1.15.8\n"; exit 0 ;;' \
        'esac' \
        'printf "run\n" >> "'"$BATS_TEST_TMPDIR"'/calls"' \
        'scope=""; list=""' \
        'case " $* " in' \
        '  *" --system "*) scope=system ;;' \
        '  *" --user "*)   scope=user   ;;' \
        'esac' \
        'case "$scope" in' \
        '  system) list="${RL_SYSTEM:-}" ;;' \
        '  user)   list="${RL_USER:-}"   ;;' \
        'esac' \
        'case " $* " in' \
        '  *" --show-disabled "*)' \
        '    case "$scope" in' \
        '      system) list="$list ${RL_SYSTEM_DISABLED:-}" ;;' \
        '      user)   list="$list ${RL_USER_DISABLED:-}"   ;;' \
        '    esac ;;' \
        'esac' \
        'for n in $list; do printf "%s\n" "$n"; done' \
        > "$FP_BIN/flatpak"
    chmod +x "$FP_BIN/flatpak"
    export _FLATHUB_FLATPAK_SHA256="$(sha256sum "$FP_BIN/flatpak" | cut -d' ' -f1)"
    export FLATPAK_TEST_MODE=1
}

# helper: write a repo config file fixture; $1=name $2..=key=value lines
_config() {
    local name="$1"; shift
    local f="$BATS_TEST_TMPDIR/$name"
    printf '%s\n' "[core]" "repo_version=1" > "$f"
    printf '%s\n' '    [remote "flathub"]' "$@" >> "$f"
}

_fake_flatpak_partial_failure() {
    _fake_flatpak
}

@test "single double-source guard: sourcing twice is a no-op" {
    . "$BATS_TEST_DIRNAME/../fx-flathub-detect.sh"
    . "$BATS_TEST_DIRNAME/../fx-flathub-detect.sh"
    command -v flathub_detect >/dev/null
    command -v flathub_enabled >/dev/null
    command -v flathub_state >/dev/null
    command -v flathub_scope >/dev/null
}

@test "enabled in system: predicate true, globals report scope=system" {
    _fake_flatpak
    export RL_SYSTEM="flathub"
    PATH="$FP_BIN:$PATH"
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 0 ]
    [ "$FLATHUB_ENABLED" = "1" ]
    [ "$FLATHUB_CONFIGURED" = "1" ]
    [ "$FLATHUB_STATE" = "enabled" ]
    [ "$FLATHUB_SCOPE" = "system" ]
    [ "$FLATHUB_BIN" = "$FP_BIN/flatpak" ]
}

@test "enabled in user only: scope=user" {
    _fake_flatpak
    export RL_USER="flathub"
    PATH="$FP_BIN:$PATH"
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 0 ]
    [ "$FLATHUB_ENABLED" = "1" ]
    [ "$FLATHUB_STATE" = "enabled" ]
    [ "$FLATHUB_SCOPE" = "user" ]
}

@test "enabled in both: scope=both" {
    _fake_flatpak
    export RL_SYSTEM="flathub"
    export RL_USER="flathub"
    PATH="$FP_BIN:$PATH"
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 0 ]
    [ "$FLATHUB_STATE" = "enabled" ]
    [ "$FLATHUB_SCOPE" = "both" ]
}

@test "configured but disabled: predicate false, state=disabled" {
    _fake_flatpak
    export RL_SYSTEM_DISABLED="flathub"
    PATH="$FP_BIN:$PATH"
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 1 ]
    [ "$FLATHUB_ENABLED" = "0" ]
    [ "$FLATHUB_CONFIGURED" = "1" ]
    [ "$FLATHUB_STATE" = "disabled" ]
}

@test "not configured: predicate false, state=not-configured, scope empty" {
    _fake_flatpak
    PATH="$FP_BIN:$PATH"
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 1 ]
    [ "$FLATHUB_ENABLED" = "0" ]
    [ "$FLATHUB_CONFIGURED" = "0" ]
    [ "$FLATHUB_STATE" = "not-configured" ]
    [ -z "$FLATHUB_SCOPE" ]
}

@test "longer-named remote (myflathub) is NOT counted" {
    _fake_flatpak
    export RL_SYSTEM="myflathub"
    PATH="$FP_BIN:$PATH"
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 1 ]
    [ "$FLATHUB_STATE" = "not-configured" ]
}

@test "partial scope query failure trusts authoritative scope, not unknown" {
    _fake_flatpak_partial_failure
    export FAIL_SYSTEM=1
    PATH="$FP_BIN:$PATH"
    lib
    flathub_detect || true
    [ "$FLATHUB_STATE" = "not-configured" ]
}

@test "flatpak absent: state=flatpak-missing, predicate false (host config excluded)" {
    export _FLATHUB_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/none-system"
    export _FLATHUB_USER_CONFIG="$BATS_TEST_TMPDIR/none-user"
    export FLATPAK_TEST_MODE=1
    local orig_path="$PATH"
    PATH=/nonexistent-bin-dir
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 1 ]
    [ "$FLATHUB_ENABLED" = "0" ]
    [ "$FLATHUB_STATE" = "flatpak-missing" ]
    [ -z "$FLATHUB_BIN" ]
    PATH="$orig_path"
}

@test "file fallback: system config with flathub is enabled (flatpak absent)" {
    # Create allowlisted path structure: /var/lib/flatpak/repo/config
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    # Write config directly to the path being tested
    printf '%s\n' "[core]" "repo_version=1" '    [remote "flathub"]' "url=https://dl.flathub.org/repo/" "gpg-verify=true" > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    export _FLATHUB_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    export _FLATHUB_USER_CONFIG="$BATS_TEST_TMPDIR/none-user"
    # Need test override for temp dir paths
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    export FLATPAK_TEST_MODE=1
    local orig_path="$PATH"
    PATH=/nonexistent-bin-dir
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 0 ]
    [ "$FLATHUB_ENABLED" = "1" ]
    [ "$FLATHUB_STATE" = "enabled" ]
    [ "$FLATHUB_SCOPE" = "system" ]
    PATH="$orig_path"
}

@test "file fallback: user config alone yields scope=user" {
    # Create allowlisted path structure: $HOME/.local/share/flatpak/repo/config
    mkdir -p "$BATS_TEST_TMPDIR/home/user/.local/share/flatpak/repo"
    # Write config directly to the path being tested
    printf '%s\n' "[core]" "repo_version=1" '    [remote "flathub"]' "url=https://dl.flathub.org/repo/" > "$BATS_TEST_TMPDIR/home/user/.local/share/flatpak/repo/config"
    export _FLATHUB_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/none-system"
    export _FLATHUB_USER_CONFIG="$BATS_TEST_TMPDIR/home/user/.local/share/flatpak/repo/config"
    # Need test override for temp dir paths
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    export FLATPAK_TEST_MODE=1
    local orig_path="$PATH"
    PATH=/nonexistent-bin-dir
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 0 ]
    [ "$FLATHUB_STATE" = "enabled" ]
    [ "$FLATHUB_SCOPE" = "user" ]
    PATH="$orig_path"
}

@test "file fallback: both configs present yield scope=both" {
    # Create allowlisted path structures
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    mkdir -p "$BATS_TEST_TMPDIR/home/user/.local/share/flatpak/repo"
    # Write configs directly to the paths being tested
    printf '%s\n' "[core]" "repo_version=1" '    [remote "flathub"]' "url=https://dl.flathub.org/repo/" > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    printf '%s\n' "[core]" "repo_version=1" '    [remote "flathub"]' "url=https://dl.flathub.org/repo/" > "$BATS_TEST_TMPDIR/home/user/.local/share/flatpak/repo/config"
    export _FLATHUB_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    export _FLATHUB_USER_CONFIG="$BATS_TEST_TMPDIR/home/user/.local/share/flatpak/repo/config"
    # Need test override for temp dir paths
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    export FLATPAK_TEST_MODE=1
    local orig_path="$PATH"
    PATH=/nonexistent-bin-dir
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 0 ]
    [ "$FLATHUB_SCOPE" = "both" ]
    PATH="$orig_path"
}

@test "file fallback: enabled=false in the section means disabled" {
    # Create allowlisted path structure
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    # Write config directly to the path being tested
    printf '%s\n' "[core]" "repo_version=1" '    [remote "flathub"]' "enabled=false" "url=https://dl.flathub.org/repo/" > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    export _FLATHUB_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    export _FLATHUB_USER_CONFIG="$BATS_TEST_TMPDIR/none-user"
    # Need test override for temp dir paths
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    export FLATPAK_TEST_MODE=1
    local orig_path="$PATH"
    PATH=/nonexistent-bin-dir
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 1 ]
    [ "$FLATHUB_ENABLED" = "0" ]
    [ "$FLATHUB_CONFIGURED" = "1" ]
    [ "$FLATHUB_STATE" = "disabled" ]
    PATH="$orig_path"
}

@test "file fallback trims whitespace and rejects malformed enabled values" {
    # Create allowlisted path structure
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    printf '%s\n' '[remote "flathub"]' ' enabled = false ' > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    export _FLATHUB_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    export _FLATHUB_USER_CONFIG="$BATS_TEST_TMPDIR/none-user"
    # Need test override for temp dir paths
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    export FLATPAK_TEST_MODE=1
    local orig_path="$PATH"
    PATH=/nonexistent-bin-dir
    lib
    flathub_detect || true
    [ "$FLATHUB_STATE" = "disabled" ]

    # Malformed enabled values are treated as disabled (fail-safe)
    printf '%s\n' '[remote "flathub"]' 'enabled = perhaps' > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    flathub_detect || true
    [ "$FLATHUB_STATE" = "disabled" ]
    PATH="$orig_path"
}

@test "file fallback: no config files at all -> no detection, state=flatpak-missing" {
    export _FLATHUB_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/none-system"
    export _FLATHUB_USER_CONFIG="$BATS_TEST_TMPDIR/none-user"
    export FLATPAK_TEST_MODE=1
    local orig_path="$PATH"
    PATH=/nonexistent-bin-dir
    lib
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 1 ]
    [ "$FLATHUB_CONFIGURED" = "0" ]
    [ "$FLATHUB_STATE" = "flatpak-missing" ]
    PATH="$orig_path"
}

@test "lazy accessors run detection at most once per shell" {
    _fake_flatpak_counting
    export RL_SYSTEM="flathub"
    PATH="$FP_BIN:$PATH"
    lib
    flathub_enabled
    flathub_state
    flathub_scope
    first=$(wc -l < "$BATS_TEST_TMPDIR/calls" 2>/dev/null || printf '0')
    flathub_enabled
    flathub_state
    flathub_scope
    flathub_enabled
    run wc -l < "$BATS_TEST_TMPDIR/calls"
    [ "$output" = "$first" ]
    [ -n "$first" ]
}

@test "flathub_detect re-runs fresh (refresh escape hatch)" {
    _fake_flatpak
    export RL_SYSTEM="flathub"
    PATH="$FP_BIN:$PATH"
    lib
    flathub_enabled
    [ "$FLATHUB_STATE" = "enabled" ]

    unset RL_SYSTEM
    flathub_detect || true
    if flathub_enabled; then rc=0; else rc=1; fi
    [ "$rc" -eq 1 ]
    [ "$FLATHUB_STATE" = "not-configured" ]
}

@test "safe inside a strict-mode caller" {
    _fake_flatpak
    export RL_SYSTEM="flathub"
    run bash -c 'set -euo pipefail; PATH="'"$FP_BIN"':$PATH"; . "'"$BATS_TEST_DIRNAME"'/../fx-flathub-detect.sh"; flathub_enabled; printf "ok:%s:%s" "$FLATHUB_STATE" "$FLATHUB_SCOPE"'
    [ "$status" -eq 0 ]
    [ "$output" = "ok:enabled:system" ]
}

@test "accessors never trip set -u and echo empty when not enabled" {
    run bash -c 'PATH=/nonexistent-bin-dir; set -u; export FLATPAK_TEST_MODE=1 _FLATHUB_SYSTEM_CONFIG="'"$BATS_TEST_TMPDIR"'/none-system" _FLATHUB_USER_CONFIG="'"$BATS_TEST_TMPDIR"'/none-user"; . "'"$BATS_TEST_DIRNAME"'/../fx-flathub-detect.sh"; flathub_enabled && rc=0 || rc=1; flathub_state; flathub_scope; exit "$rc"'
    [ "$status" -eq 1 ]
    [ "${lines[0]}" = "flatpak-missing" ]
    [ "${lines[1]}" = "empty" ]
}

@test "direct execution refuses with exit 2" {
    run bash "$BATS_TEST_DIRNAME/../fx-flathub-detect.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *source-only* ]]
}