# Fix Plan: fx-flathub-detect.sh Correctness Issues

Based on RapidReview verdict **REVISE** (cache key: `0fac4845c2bd5780-correctness`)

---

## Priority Order (Dependency-Aware)

### Phase 1: Foundation Safety (Blocks All Other Fixes)
**Must fix first — these affect caller shell safety and basic correctness**

| ID | Finding | Location | Fix |
|----|---------|----------|-----|
| F3 | `set -euo pipefail` source guard kills caller | Line 110 | Replace `return 0 2>/dev/null \|\| exit 0` with safe pattern |
| F1/F2 | Scope failure poisons global state | Lines 477-532 | Decouple scope failure handling; trust successful scopes |

---

### Phase 2: Core Detection Logic (Highest User Impact)
**Fixes that change the primary API behavior**

| ID | Finding | Location | Fix |
|----|---------|----------|-----|
| F4/F5 | Config fallback asymmetric (only on binary absent) | Lines 514-520 | Trigger fallback when `normal_answered=0` (all scopes failed) |
| F6 | `enabled=false` rejects valid flatpak values | Lines 325-328 | Accept yes/no/on/off/auto/true/false (case-insensitive) |
| F14 | Config parser regex rejects valid INI | Line 303 | Fix regex for inline comments, trailing spaces |

---

### Phase 3: Portability & Platform Support
**Fixes that enable correct operation on NixOS, macOS, BSD, etc.**

| ID | Finding | Location | Fix |
|----|---------|----------|-----|
| F9 | TOCTOU: `stat -c` non-portable (GNU only) | Lines 300, 338 | Use portable `stat` format or skip mtime check on non-GNU |
| F9 | TOCTOU: race between realpath and stat | Lines 296-300 | Read file via fd or use `flock` if available |
| F10 | NixOS/Homebrew no-op case statements | Lines 244-246, 257-259 | Remove or implement actual path allowance logic |
| F10 | NixOS `ID="nixos"` parsing fails | Line 266 | Parse `ID=` value properly (handle quotes) |
| F10 | Binary allowlist incomplete | Lines 204-206 | Add `/run/current-system/sw/bin/flatpak`, `/snap/bin/flatpak`, `/var/lib/flatpak/exports/bin/flatpak`, user-local paths |
| F10 | Homebrew Linux (Linuxbrew) unsupported | Lines 205, 258, 366, 392 | Add `/home/linuxbrew/.linuxbrew/bin/flatpak` and config paths |

---

### Phase 4: Cache & State Integrity
**Fixes for caching correctness and debug/security**

| ID | Finding | Location | Fix |
|----|---------|----------|-----|
| F7 | Cache integrity hashes outputs not inputs | Lines 586-614 | Include config mtimes, binary hash, remote-list output in hash |
| F8 | Binary allowlist incomplete (duplicative of Phase 3) | — | Covered in Phase 3 |
| F11 | Debug redaction broken | Lines 135-142 | Derive patterns from allowlists; fix glob syntax; add missing paths |
| F12 | `flathub_scope_enabled` conflates disabled/error | Lines 554-561 | Return distinct codes or add error output parameter |
| F13 | Scope reporting: empty string vs `'empty'` | Lines 186, 530, 621 | Return `'empty'` literal per spec; don't default to `'system'` |

---

### Phase 5: Testing & Validation
**Verify all fixes work and don't regress**

| Task | Description |
|------|-------------|
| Run existing bats suite | `bats test/flathub_detect.bats` (all 18 tests must pass) |
| Add regression tests | For each CRITICAL/HIGH finding: test case that would fail before fix |
| Test on target platforms | NixOS, macOS (Homebrew), BSD (stat portability) |
| Run shellcheck | `shellcheck -S style -x fx-flathub-detect.sh test/flathub_detect.bats` |
| Run RapidReview again | Same cache key to verify regression fixed |

---

## Detailed Fix Specifications

### Fix F3: Source Guard Safety (Line 110)

**Current (unsafe):**
```bash
return 0 2>/dev/null || exit 0
```

**Fixed:**
```bash
# Safe double-source guard: use subshell to isolate exit
( return 0 2>/dev/null ) || exit 0
```
Or better — check if sourced in a function context:
```bash
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 0
else
    exit 0
fi
```

---

### Fix F1/F2: Scope Failure Isolation (Lines 477-532)

**Current Problem:** Single `normal_failed` flag couples all scopes.

**New Design:**
```bash
# Track per-scope results independently
declare -A scope_result scope_has_flathub scope_normal_ok scope_disabled_ok

for scope in system user; do
    scope_normal_ok[$scope]=0
    scope_has_flathub[$scope]=0
    scope_disabled_ok[$scope]=0
    
    # ... query logic ...
    if [ "$rc" -eq 0 ]; then
        scope_normal_ok[$scope]=1
        if _flathub_has_name "$out"; then
            scope_has_flathub[$scope]=1
        fi
    fi
done

# Disabled check per-scope (only where normal_ok=1 and has_flathub=0)
for scope in system user; do
    if [ "${scope_normal_ok[$scope]}" = "1" ] && [ "${scope_has_flathub[$scope]}" = "0" ]; then
        # run --show-disabled for THIS scope only
    fi
done

# Finalize: aggregate per-scope results
# enabled = ANY scope_has_flathub=1
# disabled = ANY scope_normal_ok=1 && scope_has_flathub=0 && scope_disabled_ok=1
# not-configured = ALL scope_normal_ok=1 && ALL scope_has_flathub=0 && ALL scope_disabled_ok=0
# unknown = ANY scope_normal_ok=0 (but don't override enabled/disabled from other scopes)
```

---

### Fix F4/F5: Config Fallback Logic (Lines 514-520)

**Current:**
```bash
if [ -z "$bin" ]; then
    _flathub_probe_files
fi
```

**Fixed:**
```bash
# Fallback when binary absent OR all normal queries failed
if [ -z "$bin" ] || [ "$normal_answered" -eq 0 ]; then
    _flathub_probe_files
fi
```

---

### Fix F6: Valid Flatpak Enabled Values (Lines 325-328)

**Current:**
```bash
case "$v" in
    [Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]|0) _flathub_cf_enabled=0 ;;
    [Tt][Rr][Uu][Ee]|[Oo][Nn]|1) _flathub_cf_enabled=1 ;;
    *) _flathub_cf_enabled=0; _flathub_cf_malformed=1 ;;
esac
```

**Fixed:**
```bash
case "${v,,}" in  # lowercase (bash 4+)
    false|off|no|0|disabled) _flathub_cf_enabled=0 ;;
    true|on|yes|1|enabled|auto) _flathub_cf_enabled=1 ;;
    *) _flathub_cf_enabled=0; _flathub_cf_malformed=1 ;;
esac
```

---

### Fix F14: Config Parser Regex (Line 303)

**Current:**
```bash
local flathub_section_re='^[[:space:]]*\[remote[[:space:]]+['"'"'"]?flathub['"'"'"]?\]$'
```

**Fixed:**
```bash
# Handle: inline comments, trailing spaces, tabs, optional quotes
local flathub_section_re='^[[:space:]]*\[remote[[:space:]]+['"'"'"]?flathub['"'"'"]?\][[:space:]]*(#.*)?$'
```

Also fix line 333 — don't flag valid key=value lines as malformed:
```bash
# Only flag truly malformed (non-empty, non-comment, no =)
case "$line" in
    *=*) ;;  # key=value is fine
    ''|\#*) ;;  # empty or comment
    *);;  # other non-empty -> malformed
esac
```

---

### Fix F9: Portable stat for TOCTOU (Lines 300, 338)

**Current:**
```bash
st_before="$(stat -c '%i %Y' "$f" 2>/dev/null)" || st_before=""
```

**Fixed:**
```bash
# Portable inode+mtime detection
if stat -c '%i %Y' "$f" >/dev/null 2>&1; then
    # GNU stat (Linux)
    st_before="$(stat -c '%i %Y' "$f" 2>/dev/null)"
elif stat -f '%i %m' "$f" >/dev/null 2>&1; then
    # BSD/macOS stat
    st_before="$(stat -f '%i %m' "$f" 2>/dev/null)"
else
    st_before=""
fi
```

---

### Fix F10: NixOS Detection (Line 266)

**Current:**
```bash
[[ -r /etc/os-release ]] && while IFS= read -r line; do [[ "$line" = "ID=nixos" ]] && return 0; done < /etc/os-release; return 1
```

**Fixed:**
```bash
_flathub_check_nixos() {
    [[ -r /etc/os-release ]] || return 1
    while IFS= read -r line; do
        case "$line" in
            ID=nixos|ID="nixos"|ID='nixos') return 0 ;;
        esac
    done < /etc/os-release
    return 1
}
```

---

### Fix F11: Debug Redaction (Lines 135-142)

**Current:** Hardcoded patterns with wrong glob syntax.

**Fixed:** Derive from allowlists:
```bash
_flathub_debug() {
    [ "${_FLATHUB_DEBUG:-${SCRIPT_DEBUG:-0}}" = "1" ] || return 0
    local msg="$*"
    
    # Redact using allowlist patterns (consistent with validation)
    msg="${msg//\/home\/[^\/]*\//\/home\/<HOME>\/}"
    msg="${msg//\/Users\/[^\/]*\//\/Users\/<HOME>\/}"
    msg="${msg//\/root\//\/<ROOT>\/}"
    msg="${msg//\/run\/user\/[^\/]*\//\/run\/user\/<UID>\/}"
    msg="${msg//\/tmp\/[^\/]*\//\/tmp\/<TMP>\/}"
    msg="${msg//\/var\/lib\/flatpak\/repo\/config/<CONFIG>}"
    msg="${msg//\/etc\/flatpak\/<ETC_FLATPAK>}"
    msg="${msg//\/nix\/store\/[^\/]*\/flatpak/<NIX_FLATPAK>}"
    msg="${msg//\/nix\/store\/[^\/]*\/bin\/flatpak/<NIX_FLATPAK_BIN>}"
    msg="${msg//\/opt\/homebrew\/[^\/]*\/flatpak/<HOMEBREW_FLATPAK>}"
    msg="${msg//\/opt\/homebrew\/bin\/flatpak/<HOMEBREW_FLATPAK_BIN>}"
    msg="${msg//\/usr\/local\/[^\/]*\/flatpak/<HOMEBREW_FLATPAK>}"
    msg="${msg//\/usr\/local\/bin\/flatpak/<HOMEBREW_FLATPAK_BIN>}"
    msg="${msg//\/home\/linuxbrew\/\.linuxbrew\/bin\/flatpak/<LINUXBREW_FLATPAK_BIN>}"
    msg="${msg//\/var\/lib\/flatpak\/exports\/bin\/flatpak/<FLATPAK_EXPORT_BIN>}"
    msg="${msg//\/run\/current-system\/sw\/bin\/flatpak/<NIXOS_PROFILE_BIN>}"
    msg="${msg//bin=<validated>/bin=<validated>}"
    msg="${msg//bin=[^ ]*/bin=<REDACTED>}"
    
    printf '%s\n' "fx-flathub-detect: $msg" >&2
}
```

---

### Fix F12/F13: Scope Reporting (Lines 186, 530, 621)

**Current:** Returns empty string, defaults to 'system'.

**Fixed:**
```bash
_flathub_normalize_scope() {
    # ... existing logic ...
    if [ "$has_system" = "1" ] && [ "$has_user" = "1" ]; then
        printf '%s\n' "both"
    elif [ "$has_system" = "1" ]; then
        printf '%s\n' "system"
    elif [ "$has_user" = "1" ]; then
        printf '%s\n' "user"
    else
        printf '%s\n' "empty"  # Not empty string
    fi
}

flathub_scope() { _flathub_ensure; printf '%s\n' "${FLATHUB_SCOPE:-empty}"; }
```

Remove line 530 default-to-system:
```bash
# REMOVE: [ -n "$FLATHUB_SCOPE" ] || FLATHUB_SCOPE=system
```

---

### Fix F7: Cache Integrity (Lines 586-614)

**Current:** Hashes only 5 output globals.

**Fixed:** Include input sources in hash:
```bash
_flathub_compute_cache_hash() {
    local hash_input="${FLATHUB_ENABLED:-}:${FLATHUB_CONFIGURED:-}:${FLATHUB_STATE:-}:${FLATHUB_SCOPE:-}:${FLATHUB_BIN:-}"
    
    # Add input fingerprints
    if [ -n "${FLATHUB_BIN:-}" ] && [ -f "${FLATHUB_BIN}" ]; then
        hash_input="${hash_input}:$(_flathub_file_fingerprint "${FLATHUB_BIN}")"
    fi
    local sys_cfg="$(_flathub_system_config)"
    if [ -r "$sys_cfg" ]; then
        hash_input="${hash_input}:sys:$(_flathub_file_fingerprint "$sys_cfg")"
    fi
    local usr_cfg="$(_flathub_user_config)"
    if [ -r "$usr_cfg" ]; then
        hash_input="${hash_input}:usr:$(_flathub_file_fingerprint "$usr_cfg")"
    fi
    
    # ... rest of hash computation ...
}

_flathub_file_fingerprint() {
    # Portable: mtime:size (no stat -c dependency)
    if command -v stat >/dev/null 2>&1; then
        stat -c '%Y:%s' "$1" 2>/dev/null || stat -f '%m:%z' "$1" 2>/dev/null || printf 'unknown'
    else
        printf 'unknown'
    fi
}
```

---

## Test Matrix (Must Pass Before Re-Review)

| Test | Platform | Expected |
|------|----------|----------|
| `bats test/flathub_detect.bats` | Linux | All 18 pass |
| Scope failure isolation | Linux | One scope fails → other scope result preserved |
| Config fallback on command failure | Linux | Binary exists but fails → config probed |
| NixOS path detection | NixOS | Binary + config detected |
| macOS Homebrew | macOS | Binary + config detected |
| BSD stat portability | FreeBSD/OpenBSD | No mtime check crash |
| `set -euo pipefail` caller | Linux | No shell exit on source/eval |
| Debug redaction | Linux | Sensitive paths redacted |
| Cache invalidation | Linux | Config change → fresh detection |

---

## Re-Review Checklist

After implementing all fixes:
1. [ ] All existing tests pass
2. [ ] New regression tests added for each CRITICAL/HIGH finding
3. [ ] `shellcheck -S style -x` clean
4. [ ] `bash -n` clean
5. [ ] Manual test on NixOS/macOS/BSD if available
6. [ ] Run RapidReview again with same cache key
7. [ ] Expect verdict: **APPROVE**

---

### Phase 6: Council Mandatory Additions (v2)
**Required by RedCouncilReview verdict for APPROVE — these 6 items are non-negotiable**

| ID | Finding | Location | Fix |
|----|---------|----------|-----|
| C1 | No reachability probe before metadata trust | New: add before step 2 | Add `flatpak --version` + `flatpak remote-ls --columns=name` health check before any metadata read; fail closed if binary unreachable |
| C2 | Cache fingerprints use mtime:size (1-sec granularity), no content hash | Lines 735-743 `_flathub_file_fingerprint` | Replace with SHA-256 content hash of repo `summary` + `refs` files; store alongside mtime:size as defense-in-depth |
| C3 | TOCTOU window in dual-path config validation (original → realpath → canonical) | Lines 330-336, 386-394 | Single-path fd-based validation: `exec {fd}<"$f"` → `fstat` on fd → read via fd → close fd; no symlink race |
| C4 | Binary allowlist retains `_FLATHUB_FLATPAK_SHA256` escape hatch (bypasses allowlist entirely) | Lines 242-248 | Remove escape hatch OR require signed commit verification via `flatpak verify`; no unauthenticated bypass |
| C5 | Test overrides bleed into prod (`_FLATHUB_SYSTEM_CONFIG`/`_FLATHUB_USER_CONFIG` work unconditionally) | Lines 269, 283 | Cryptographic separation: reject override env vars unless `FLATPAK_TEST_MODE=1` (build-time flag) AND test fixture signature matches |
| C6 | State machine discards partial knowledge — "unknown" swallows "system-known user-unknown" | Lines 622-650 | Emit per-scope result object: `{scope, enabled, reachable, error?}` in new global `FLATHUB_SCOPES_JSON`; legacy `FLATHUB_STATE` preserved for compat |

---

## Estimated Effort (Updated)

| Phase | Files Changed | Est. Time |
|-------|---------------|-----------|
| Phase 1 | 1 (fx-flathub-detect.sh) | 30 min |
| Phase 2 | 1 | 45 min |
| Phase 3 | 1 | 60 min |
| Phase 4 | 1 | 45 min |
| Phase 5 | 1 + test file | 60 min |
| Phase 6 (Council Mandatory) | 1 + test file | 90 min |
| **Total** | | **~5.5 hours** |