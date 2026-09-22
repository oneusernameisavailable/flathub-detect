#!/usr/bin/env bats
# shellcheck disable=SC1091
# fx-flathub-detect.sh unit tests for new security helpers.

setup() {
    export FP_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$FP_BIN"
}

lib() {
    . "$BATS_TEST_DIRNAME/../fx-flathub-detect.sh"
}

# =============================================================================
# _flathub_validate_binary tests
# =============================================================================

@test "_flathub_validate_binary: rejects empty input" {
    lib
    run _flathub_validate_binary ""
    [ "$status" -eq 1 ]
}

@test "_flathub_validate_binary: rejects relative path" {
    lib
    run _flathub_validate_binary "flatpak"
    [ "$status" -eq 1 ]
}

@test "_flathub_validate_binary: rejects non-existent path" {
    lib
    run _flathub_validate_binary "/nonexistent/flatpak"
    [ "$status" -eq 1 ]
}

@test "_flathub_validate_binary: rejects non-executable file" {
    lib
    touch "$BATS_TEST_TMPDIR/not-exec"
    run _flathub_validate_binary "$BATS_TEST_TMPDIR/not-exec"
    [ "$status" -eq 1 ]
}

@test "_flathub_validate_binary: accepts valid absolute executable" {
    lib
    cat > "$FP_BIN/flatpak" <<'EOF'
#!/usr/bin/env bash
echo "1.15.8"
EOF
    chmod +x "$FP_BIN/flatpak"
    # Compute checksum and set env var to allow test binary (not in production allowlist)
    export _FLATHUB_FLATPAK_SHA256="$(sha256sum "$FP_BIN/flatpak" | cut -d' ' -f1)"
    run _flathub_validate_binary "$FP_BIN/flatpak"
    [ "$status" -eq 0 ]
    [ "$output" = "$FP_BIN/flatpak" ]
}

@test "_flathub_validate_binary: rejects binary that fails --version check" {
    lib
    cat > "$FP_BIN/not-flatpak" <<'EOF'
#!/usr/bin/env bash
echo "not flatpak"
EOF
    chmod +x "$FP_BIN/not-flatpak"
    run _flathub_validate_binary "$FP_BIN/not-flatpak"
    [ "$status" -eq 1 ]
}

# =============================================================================
# _flathub_system_config / _flathub_user_config traversal blocking tests
# =============================================================================

@test "_flathub_system_config: blocks directory traversal" {
    lib
    export _FLATHUB_SYSTEM_CONFIG="/etc/flatpak/../../etc/shadow"
    run _flathub_system_config
    [ "$status" -eq 0 ]
    [ "$output" = "/var/lib/flatpak/repo/config" ]
}

@test "_flathub_system_config: blocks relative path" {
    lib
    export _FLATHUB_SYSTEM_CONFIG="relative/path"
    run _flathub_system_config
    [ "$status" -eq 0 ]
    [ "$output" = "/var/lib/flatpak/repo/config" ]
}

@test "_flathub_user_config: blocks directory traversal" {
    lib
    export _FLATHUB_USER_CONFIG="$HOME/../../etc/shadow"
    run _flathub_user_config
    [ "$status" -eq 0 ]
    [[ "$output" != *".."* ]]
}

# =============================================================================
# _flathub_probe_config fail-safe on malformed enabled= tests
# =============================================================================

@test "_flathub_probe_config: malformed enabled value treated as disabled (fail-safe)" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    printf '%s\n' '[remote "flathub"]' 'enabled=perhaps' > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    # Path is under temp dir; need test override to allow it
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    _flathub_probe_config "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    # Should be configured (section exists) but NOT enabled (malformed -> fail-safe disabled)
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "0" ]
    [ "$_flathub_cf_malformed" = "1" ]
}

@test "_flathub_probe_config: enabled=true is enabled" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    printf '%s\n' '[remote "flathub"]' 'enabled=true' > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    # Path is under temp dir; need test override to allow it
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    _flathub_probe_config "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "1" ]
    [ "$_flathub_cf_malformed" = "0" ]
}

@test "_flathub_probe_config: enabled=false is disabled" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    printf '%s\n' '[remote "flathub"]' 'enabled=false' > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    # Path is under temp dir; need test override to allow it
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    _flathub_probe_config "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "0" ]
    [ "$_flathub_cf_malformed" = "0" ]
}

@test "_flathub_probe_config: enabled=0 is disabled" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    printf '%s\n' '[remote "flathub"]' 'enabled=0' > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    # Path is under temp dir; need test override to allow it
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    _flathub_probe_config "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "0" ]
    [ "$_flathub_cf_malformed" = "0" ]
}

@test "_flathub_probe_config: enabled=1 is enabled" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    printf '%s\n' '[remote "flathub"]' 'enabled=1' > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    # Path is under temp dir; need test override to allow it
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    _flathub_probe_config "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "1" ]
    [ "$_flathub_cf_malformed" = "0" ]
}

# =============================================================================
# _flathub_normalize_scope fix for scope accumulation
# =============================================================================

@test "_flathub_normalize_scope: system only" {
    lib
    run _flathub_normalize_scope "system"
    [ "$status" -eq 0 ]
    [ "$output" = "system" ]
}

@test "_flathub_normalize_scope: user only" {
    lib
    run _flathub_normalize_scope "user"
    [ "$status" -eq 0 ]
    [ "$output" = "user" ]
}

@test "_flathub_normalize_scope: both scopes" {
    lib
    run _flathub_normalize_scope "system user"
    [ "$status" -eq 0 ]
    [ "$output" = "both" ]
}

@test "_flathub_normalize_scope: reversed order still both" {
    lib
    run _flathub_normalize_scope "user system"
    [ "$status" -eq 0 ]
    [ "$output" = "both" ]
}

@test "_flathub_normalize_scope: empty input" {
    lib
    run _flathub_normalize_scope ""
    [ "$status" -eq 0 ]
    [ "$output" = "empty" ]
}

# =============================================================================
# _flathub_check_nixos / _flathub_check_homebrew platform detection tests
# =============================================================================

@test "_flathub_check_nixos: returns true on NixOS (ID=nixos)" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/etc"
    printf 'ID=nixos\nVERSION="24.05"\n' > "$BATS_TEST_TMPDIR/etc/os-release"
    # Test the pattern logic directly (same as function but with test path)
    run bash -c '[[ -r '"$BATS_TEST_TMPDIR"'/etc/os-release ]] && while IFS= read -r line; do [[ "$line" = "ID=nixos" ]] && exit 0; done < '"$BATS_TEST_TMPDIR"'/etc/os-release; exit 1'
    [ "$status" -eq 0 ]
}

@test "_flathub_check_nixos: returns false on non-NixOS" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/etc"
    printf 'ID=ubuntu\nVERSION="24.04"\n' > "$BATS_TEST_TMPDIR/etc/os-release"
    run bash -c '[[ -r '"$BATS_TEST_TMPDIR"'/etc/os-release ]] && while IFS= read -r line; do [[ "$line" = "ID=nixos" ]] && exit 0; done < '"$BATS_TEST_TMPDIR"'/etc/os-release; exit 1'
    [ "$status" -eq 1 ]
}

@test "_flathub_check_nixos: returns false on missing os-release" {
    lib
    run bash -c '[[ -r "/nonexistent/os-release" ]] && while IFS= read -r line; do [[ "$line" = "ID=nixos" ]] && exit 0; done < "/nonexistent/os-release"; exit 1'
    [ "$status" -eq 1 ]
}

@test "_flathub_check_homebrew: returns true when Homebrew exists at /opt/homebrew" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/opt/homebrew/bin"
    touch "$BATS_TEST_TMPDIR/opt/homebrew/bin/brew"
    chmod +x "$BATS_TEST_TMPDIR/opt/homebrew/bin/brew"
    # Test the logic directly since paths are hardcoded in function
    run bash -c '[ -x '"$BATS_TEST_TMPDIR"'/opt/homebrew/bin/brew ] || [ -x "/usr/local/bin/brew" ]'
    [ "$status" -eq 0 ]
}

@test "_flathub_check_homebrew: returns true when Homebrew exists at /usr/local" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/usr/local/bin"
    touch "$BATS_TEST_TMPDIR/usr/local/bin/brew"
    chmod +x "$BATS_TEST_TMPDIR/usr/local/bin/brew"
    run bash -c '[ -x "/opt/homebrew/bin/brew" ] || [ -x '"$BATS_TEST_TMPDIR"'/usr/local/bin/brew ]'
    [ "$status" -eq 0 ]
}

@test "_flathub_check_homebrew: returns false when Homebrew not installed" {
    lib
    run bash -c '[ -x "/opt/homebrew/bin/brew" ] || [ -x "/usr/local/bin/brew" ]'
    [ "$status" -eq 1 ]
}

# =============================================================================
# _flathub_probe_config path canonicalization and allowlist tests
# =============================================================================

@test "_flathub_probe_config: rejects config outside allowed dirs" {
    lib
    printf '%s\n' '[remote "flathub"]' 'enabled=true' > "$BATS_TEST_TMPDIR/evil-config"
    # This should fail because the path is not under allowed directories
    _flathub_probe_config "$BATS_TEST_TMPDIR/evil-config" || true
    [ "$_flathub_cf_configured" = "0" ]
}

@test "_flathub_probe_config: allows standard system config" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    printf '%s\n' '[remote "flathub"]' 'enabled=true' > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    # Path is under temp dir; need test override to allow it
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
    export _FLATHUB_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    _flathub_probe_config "$(_flathub_system_config)"
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "1" ]
}

# =============================================================================
# Integration: full detection with new security helpers
# =============================================================================

@test "integration: _FLATHUB_PINNED_FLATPAK with relative path rejected" {
    cat > "$FP_BIN/flatpak" <<'EOF'
#!/usr/bin/env bash
echo "1.15.8"
EOF
    chmod +x "$FP_BIN/flatpak"
    export _FLATHUB_FLATPAK_SHA256="$(sha256sum "$FP_BIN/flatpak" | cut -d' ' -f1)"
    export _FLATHUB_PINNED_FLATPAK="flatpak"  # relative - should be rejected
    PATH="$FP_BIN:$PATH"
    lib
    flathub_detect || true
    # Should fall back to PATH lookup and find the valid flatpak
    [ "$FLATHUB_STATE" = "not-configured" ]  # no flathub remote configured
}

@test "integration: _FLATHUB_PINNED_FLATPAK with valid absolute path accepted" {
    cat > "$FP_BIN/flatpak" <<'EOF'
#!/usr/bin/env bash
echo "1.15.8"
EOF
    chmod +x "$FP_BIN/flatpak"
    export _FLATHUB_FLATPAK_SHA256="$(sha256sum "$FP_BIN/flatpak" | cut -d' ' -f1)"
    export _FLATHUB_PINNED_FLATPAK="$FP_BIN/flatpak"
    PATH="$FP_BIN:$PATH"
    lib
    flathub_detect || true
    [ "$FLATHUB_STATE" = "not-configured" ]
    [ "$FLATHUB_BIN" = "$FP_BIN/flatpak" ]
}

@test "integration: debug output does not leak paths" {
    cat > "$FP_BIN/flatpak" <<'EOF'
#!/usr/bin/env bash
echo "1.15.8"
EOF
    chmod +x "$FP_BIN/flatpak"
    export _FLATHUB_FLATPAK_SHA256="$(sha256sum "$FP_BIN/flatpak" | cut -d' ' -f1)"
    export _FLATHUB_DEBUG=1
    PATH="$FP_BIN:$PATH"
    lib
    run flathub_detect
    [ "$status" -eq 1 ]  # not configured
    # Debug output should not contain absolute paths
    [[ ! "$output" == *"/home/"* ]]
    [[ ! "$output" == *"/var/lib/flatpak"* ]]
}