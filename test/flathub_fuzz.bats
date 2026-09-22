#!/usr/bin/env bats
# shellcheck disable=SC1091
# fx-flathub-detect.sh fuzz tests for config parser and binary validator.
# Property-based tests generating random/malformed inputs to find edge cases.

setup() {
    export FP_BIN="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$FP_BIN"
    export _FLATHUB_ALLOW_TEST_OVERRIDES=1
    export _FLATHUB_TEST_ALLOW_CONFIG_DIRS="$BATS_TEST_TMPDIR"
}

lib() {
    . "$BATS_TEST_DIRNAME/../fx-flathub-detect.sh"
}

# =============================================================================
# Fuzz: _flathub_probe_config with malformed INI files
# =============================================================================

@test "fuzz: config parser handles empty file" {
    lib
    printf '' > "$BATS_TEST_TMPDIR/empty.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/empty.conf" || true
    [ "$_flathub_cf_configured" = "0" ]
}

@test "fuzz: config parser handles only comments" {
    lib
    printf '# comment\n# another\n' > "$BATS_TEST_TMPDIR/comments.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/comments.conf" || true
    [ "$_flathub_cf_configured" = "0" ]
}

@test "fuzz: config parser handles section without closing bracket" {
    lib
    printf '[remote "flathub"\nenabled=true\n' > "$BATS_TEST_TMPDIR/unclosed.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/unclosed.conf" || true
    [ "$_flathub_cf_configured" = "0" ]
}

@test "fuzz: config parser handles multiple flathub sections (last wins)" {
    lib
    printf '[remote "flathub"]\nenabled=true\n[remote "flathub"]\nenabled=false\n' > "$BATS_TEST_TMPDIR/multi.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/multi.conf" || true
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "0" ]  # last section wins
}

@test "fuzz: config parser handles keys without section" {
    lib
    printf 'enabled=true\nurl=https://example.com\n' > "$BATS_TEST_TMPDIR/nosection.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/nosection.conf" || true
    [ "$_flathub_cf_configured" = "0" ]
}

@test "fuzz: config parser handles equals in value" {
    lib
    printf '[remote "flathub"]\nurl=https://example.com?a=b&c=d\n' > "$BATS_TEST_TMPDIR/equals.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/equals.conf" || true
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "1" ]
}

@test "fuzz: config parser handles whitespace variations (standard only)" {
    lib
    # Supported: leading/trailing whitespace, single space between tokens
    # NOT supported: multiple spaces between "remote" and "flathub"
    # This test documents the actual supported format
    printf '[remote "flathub"]\nenabled=true\n' > "$BATS_TEST_TMPDIR/whitespace.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/whitespace.conf" || true
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "1" ]
}

@test "fuzz: config parser handles single quotes on section (regex supports)" {
    lib
    # The regex [\"']? supports single quotes. Test via config parser.
    printf "[remote 'flathub']\nenabled=true\n" > "$BATS_TEST_TMPDIR/singlequote.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/singlequote.conf" || true
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "1" ]
}

@test "fuzz: config parser handles no quotes on section" {
    lib
    printf '[remote flathub]\nenabled=true\n' > "$BATS_TEST_TMPDIR/noquote.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/noquote.conf" || true
    [ "$_flathub_cf_configured" = "1" ]
    [ "$_flathub_cf_enabled" = "1" ]
}

@test "fuzz: config parser handles malformed enabled values (fail-safe)" {
    lib
    # These are explicitly NOT in the truthy/falsy lists -> malformed -> disabled
    local malformed_values=("maybe" "truee" "falsee" "2" "-1" "true false" "true\nfalse" "")
    for val in "${malformed_values[@]}"; do
        printf '[remote "flathub"]\nenabled=%s\n' "$val" > "$BATS_TEST_TMPDIR/malformed.conf"
        _flathub_probe_config "$BATS_TEST_TMPDIR/malformed.conf" || true
        # All malformed should result in disabled (fail-safe)
        [ "$_flathub_cf_enabled" = "0" ] || { echo "Failed for value: $val"; return 1; }
        [ "$_flathub_cf_malformed" = "1" ] || { echo "malformed not flagged for: $val"; return 1; }
    done
    
    # These ARE valid truthy/falsy values -> should work normally
    local valid_truthy=("true" "on" "yes" "1" "enabled" "auto")
    for val in "${valid_truthy[@]}"; do
        printf '[remote "flathub"]\nenabled=%s\n' "$val" > "$BATS_TEST_TMPDIR/valid.conf"
        _flathub_probe_config "$BATS_TEST_TMPDIR/valid.conf" || true
        [ "$_flathub_cf_enabled" = "1" ] || { echo "Failed for truthy value: $val"; return 1; }
        [ "$_flathub_cf_malformed" = "0" ] || { echo "valid marked malformed: $val"; return 1; }
    done
    
    local valid_falsy=("false" "off" "no" "0" "disabled")
    for val in "${valid_falsy[@]}"; do
        printf '[remote "flathub"]\nenabled=%s\n' "$val" > "$BATS_TEST_TMPDIR/valid.conf"
        _flathub_probe_config "$BATS_TEST_TMPDIR/valid.conf" || true
        [ "$_flathub_cf_enabled" = "0" ] || { echo "Failed for falsy value: $val"; return 1; }
        [ "$_flathub_cf_malformed" = "0" ] || { echo "valid marked malformed: $val"; return 1; }
    done
}

@test "fuzz: config parser handles very long lines" {
    lib
    local long_val="$(printf 'a%.0s' {1..10000})"
    printf '[remote "flathub"]\nurl=%s\n' "$long_val" > "$BATS_TEST_TMPDIR/long.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/long.conf" || true
    [ "$_flathub_cf_configured" = "1" ]
}

@test "fuzz: config parser handles binary/null bytes in file" {
    lib
    printf '[remote "flathub"]\nenabled=true\n' > "$BATS_TEST_TMPDIR/binary.conf"
    printf '\x00\x01\x02' >> "$BATS_TEST_TMPDIR/binary.conf"
    _flathub_probe_config "$BATS_TEST_TMPDIR/binary.conf" || true
    [ "$_flathub_cf_configured" = "1" ]
}

# =============================================================================
# Fuzz: _flathub_validate_binary edge cases
# =============================================================================

@test "fuzz: binary validator rejects paths with special chars" {
    lib
    local bad_paths=("/bin/flatpak;" "/bin/flatpak\$" "/bin/flatpak\`" "/bin/flatpak|" "/bin/flatpak&")
    for p in "${bad_paths[@]}"; do
        run _flathub_validate_binary "$p"
        [ "$status" -eq 1 ] || { echo "Should reject: $p"; return 1; }
    done
}

@test "fuzz: binary validator rejects directory paths" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/fakebin"
    run _flathub_validate_binary "$BATS_TEST_TMPDIR/fakebin"
    [ "$status" -eq 1 ]
}

@test "fuzz: binary validator rejects symlinks to non-flatpak" {
    lib
    cat > "$FP_BIN/notflatpak" <<'EOF'
#!/usr/bin/env bash
echo "not flatpak"
EOF
    chmod +x "$FP_BIN/notflatpak"
    ln -s "$FP_BIN/notflatpak" "$BATS_TEST_TMPDIR/fakeflatpak"
    run _flathub_validate_binary "$BATS_TEST_TMPDIR/fakeflatpak"
    [ "$status" -eq 1 ]
}

@test "fuzz: binary validator handles very long path" {
    lib
    local long_path="/usr/bin/$(printf 'a%.0s' {1..1000})"
    run _flathub_validate_binary "$long_path"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Fuzz: _flathub_system_config / _flathub_user_config path edge cases
# =============================================================================

@test "fuzz: system config rejects various traversal attempts" {
    lib
    local traversals=(
        "/var/lib/flatpak/../../etc/passwd"
        "/var/lib/flatpak/repo/../config"
        "/var/lib/flatpak/repo/config/.."
        "/var/lib/flatpak/repo/config/../.."
    )
    for p in "${traversals[@]}"; do
        export _FLATHUB_SYSTEM_CONFIG="$p"
        run _flathub_system_config
        # Should fall back to default
        [ "$output" = "/var/lib/flatpak/repo/config" ] || { echo "Failed for: $p got: $output"; return 1; }
    done
    
    # These are valid (no ..) - should be accepted as-is (then canonicalized later)
    local valid_paths=(
        "/var/lib/flatpak/././repo/config"
        "/var/lib/flatpak//repo//config"
    )
    for p in "${valid_paths[@]}"; do
        export _FLATHUB_SYSTEM_CONFIG="$p"
        run _flathub_system_config
        # Should return the path as-is (no fallback)
        [[ "$output" == /var/lib/flatpak* ]] || { echo "Failed for valid: $p got: $output"; return 1; }
    done
}

@test "fuzz: user config rejects various traversal attempts" {
    lib
    local traversals=(
        "$HOME/../../etc/passwd"
        "$HOME/.local/share/flatpak/../../config"
        "$HOME/.local/share/flatpak/repo/../config"
    )
    for p in "${traversals[@]}"; do
        export _FLATHUB_USER_CONFIG="$p"
        run _flathub_user_config
        # Should fall back to default (no .. in output)
        [[ "$output" != *".."* ]] || { echo "Failed for: $p got: $output"; return 1; }
    done
}

# =============================================================================
# Fuzz: _flathub_normalize_scope edge cases
# =============================================================================

@test "fuzz: normalize scope handles duplicates" {
    lib
    run _flathub_normalize_scope "system system user user"
    [ "$output" = "both" ]
}

@test "fuzz: normalize scope handles extra whitespace" {
    lib
    run _flathub_normalize_scope "  system   user  "
    [ "$output" = "both" ]
}

@test "fuzz: normalize scope handles unknown tokens (ignores them)" {
    lib
    run _flathub_normalize_scope "system unknown user invalid"
    [ "$output" = "both" ]
}

# =============================================================================
# Fuzz: _flathub_has_name edge cases
# =============================================================================

@test "fuzz: has_name handles empty input" {
    lib
    run _flathub_has_name ""
    [ "$status" -eq 1 ]
}

@test "fuzz: has_name handles only newlines" {
    lib
    run _flathub_has_name $'\n\n\n'
    [ "$status" -eq 1 ]
}

@test "fuzz: has_name handles similar names" {
    lib
    run _flathub_has_name "flathub-beta"
    [ "$status" -eq 1 ]
    run _flathub_has_name "myflathub"
    [ "$status" -eq 1 ]
    run _flathub_has_name "flathub "
    [ "$status" -eq 1 ]
    run _flathub_has_name " flathub"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Integration fuzz: full detection with random configs
# =============================================================================

@test "fuzz: full detection with random config permutations" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    local configs=(
        '[remote "flathub"]'
        '[remote "flathub"]\nenabled=true'
        '[remote "flathub"]\nenabled=false'
        '[remote "flathub"]\nenabled=maybe'
        '[remote "flathub"]\nurl=https://dl.flathub.org/repo/'
        '[remote "flathub"]\nenabled=true\nurl=https://dl.flathub.org/repo/'
        '[core]\nrepo_version=1\n[remote "flathub"]\nenabled=true'
    )
    for config in "${configs[@]}"; do
        printf '%s\n' "$config" > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
        export _FLATHUB_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
        export _FLATHUB_USER_CONFIG="$BATS_TEST_TMPDIR/none-user"
        flathub_detect || true
        # Should not crash, should produce valid state
        [[ "$FLATHUB_STATE" =~ ^(enabled|disabled|not-configured|unknown|flatpak-missing)$ ]] || {
            echo "Invalid state: $FLATHUB_STATE for config: $config"
            return 1
        }
    done
}

# =============================================================================
# Stress: rapid repeated detection calls
# =============================================================================

@test "stress: rapid repeated flathub_detect calls" {
    lib
    mkdir -p "$BATS_TEST_TMPDIR/var/lib/flatpak/repo"
    printf '[remote "flathub"]\nenabled=true\n' > "$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    export _FLATHUB_SYSTEM_CONFIG="$BATS_TEST_TMPDIR/var/lib/flatpak/repo/config"
    export _FLATHUB_USER_CONFIG="$BATS_TEST_TMPDIR/none-user"
    for i in {1..50}; do
        flathub_detect || true
        [ "$FLATHUB_STATE" = "enabled" ] || { echo "Failed at iteration $i"; return 1; }
    done
}