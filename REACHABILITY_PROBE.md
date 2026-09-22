# Network Reachability Probe for fx-flathub-detect.sh

## Design

Optional depth-2 check that verifies the Flathub remote is actually reachable (not just configured). Activated via environment variable to maintain backward compatibility.

---

## API Addition

```bash
# New accessor
flathub_reachable() { _flathub_ensure; [ "${FLATHUB_REACHABLE:-0}" = "1" ]; }

# New state values (extends FLATHUB_STATE)
# enabled | disabled | not-configured | unknown | flatpak-missing | unreachable
```

---

## Implementation

### 1. Add to `flathub_detect()` — after reachability probe (C1)

```bash
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
    _flathub_debug "probing Flathub remote connectivity"
    local reachable=0
    if "$bin" remote-info flathub >/dev/null 2>&1; then
        reachable=1
        _flathub_debug "Flathub remote reachable"
    else
        _flathub_debug "Flathub remote UNREACHABLE (network/DNS/TLS/mirror issue)"
    fi
    FLATHUB_REACHABLE=$reachable
fi
```

### 2. Add `FLATHUB_REACHABLE` to globals initialization

```bash
FLATHUB_ENABLED=0
FLATHUB_CONFIGURED=0
FLATHUB_STATE=not-configured
FLATHUB_SCOPE=""
FLATHUB_BIN=""
FLATHUB_REACHABLE=0          # NEW
FLATHUB_SCOPES_JSON=""       # per-scope detailed results (C6)
_flathub_files_malformed=0
_FLATHUB_CACHE_HASH=""       # reset cache hash for fresh detection
```

### 3. Add `FLATHUB_REACHABLE` to cache hash

```bash
_flathub_compute_cache_hash() {
    local hash_input="${FLATHUB_ENABLED:-}:${FLATHUB_CONFIGURED:-}:${FLATHUB_STATE:-}:${FLATHUB_SCOPE:-}:${FLATHUB_BIN:-}:${FLATHUB_REACHABLE:-}:${FLATHUB_SCOPES_JSON:-}"
    # ... rest unchanged
}
```

### 4. Add accessor function

```bash
# ---------------------------------------------------------------------------
# Accessor functions (lazy + cached; echo empty string where unset)
# ---------------------------------------------------------------------------
flathub_enabled() { _flathub_ensure; [ "${FLATHUB_ENABLED:-0}" = "1" ]; }
flathub_state()   { _flathub_ensure; printf '%s\n' "${FLATHUB_STATE:-not-configured}"; }
flathub_scope()   { _flathub_ensure; printf '%s\n' "${FLATHUB_SCOPE:-empty}"; }
flathub_reachable() { _flathub_ensure; [ "${FLATHUB_REACHABLE:-0}" = "1" ]; }  # NEW
```

### 5. Update state machine to include `unreachable`

```bash
# In finalize section, add new state:
if [ "$any_enabled" = "1" ]; then
    FLATHUB_ENABLED=1
    FLATHUB_CONFIGURED=1
    if [ "${FLATHUB_REACHABLE:-0}" = "0" ] && [ "${FLATHUB_PROBE_REACHABILITY:-0}" = "1" ]; then
        FLATHUB_STATE=unreachable
    else
        FLATHUB_STATE=enabled
    fi
    # ...
elif [ "$any_disabled" = "1" ] || [ "$any_configured" = "1" ]; then
    # ...
```

---

## Consumer Usage

```bash
# Enable reachability probe (opt-in)
export FLATHUB_PROBE_REACHABILITY=1

. /path/to/fx-flathub-detect.sh

if flathub_enabled; then
    echo "Flathub is enabled (scope: $(flathub_scope))"
    if flathub_reachable; then
        echo "  → Flathub remote is reachable, safe to install"
        flatpak install flathub org.gnome.Builder
    else
        echo "  ⚠ Flathub configured but UNREACHABLE — install may fail"
        echo "     Check network/DNS/mirror: flatpak remote-info flathub"
    fi
else
    case "$(flathub_state)" in
        disabled)       echo "Flathub disabled — run: flatpak remote-modify --enable flathub" ;;
        not-configured) echo "Flathub not configured — run: flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo" ;;
        flatpak-missing) echo "Flatpak not installed" ;;
        unreachable)    echo "Flathub enabled but remote unreachable — network issue" ;;
        *)              echo "Flathub state unknown" ;;
    esac
fi
```

---

## Behavior Matrix

| Config State | Network | `FLATHUB_PROBE_REACHABILITY=0` | `FLATHUB_PROBE_REACHABILITY=1` |
|--------------|---------|--------------------------------|--------------------------------|
| Enabled | Up | `enabled`, `reachable=1` (default) | `enabled`, `reachable=1` |
| Enabled | Down | `enabled`, `reachable=1` (default) | `unreachable`, `reachable=0` |
| Disabled | — | `disabled` | `disabled` |
| Not-configured | — | `not-configured` | `not-configured` |
| Flatpak missing | — | `flatpak-missing` | `flatpak-missing` |
| Binary unresponsive | — | `unknown` / fallback | `unknown` / fallback |

---

## Design Rationale

1. **Opt-in only** — Default behavior unchanged; no network calls unless explicitly requested
2. **Graceful degradation** — If `remote-info` fails, marks `unreachable` but doesn't break detection
3. **Cache-friendly** — Reachability included in cache hash; re-probed on cache invalidation
3. **Consumer control** — Caller decides what to do with `unreachable` (warn, retry, fallback)
4. **Scope-aware** — Could extend to per-scope reachability in `FLATHUB_SCOPES_JSON`

---

## Implementation Notes

- `flatpak remote-info flathub` is read-only, fast (~200-500ms), no auth required
- Timeout: consider wrapping with `timeout 5` if available
- IPv6/IPv4: flatpak handles both
- Proxy: respects `http_proxy`/`https_proxy` env vars
- Mirrors: tests primary Flathub URL; mirror selection is flatpak-internal