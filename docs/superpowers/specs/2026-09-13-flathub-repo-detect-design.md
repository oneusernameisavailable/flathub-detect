# fx-flathub-detect.sh — design

Date: 2026-09-13
Status: approved in conversation (2026-09-13)

## Problem

Other build scripts need to know whether the Flathub remote is **enabled** on
the current system (and if so, in which installation scope), so they can decide
whether to add it (`flatpak remote-add`) or run a `flatpak install flathub …`.
This is a source-only bash library consumed by other scripts (sibling to
`OSDetect/detect-os.sh` and `flatpakInstallDetect/flatpak-detect.sh`).

## Decision — "enabled" means

- **Scope:** enabled = flathub is enabled in ANY installation, system **or**
  user (`flatpak_scope` reports `system`/`user`/`both`). This covers both
  root-driven installs (`sudo flatpak install` → system) and plain-user
  installs.
- **Predicate (command path, authoritative):** an exact, whole-line `flathub`
  match in `flatpak remote-list --$scope --columns=name`. `remote-list` hides
  disabled remotes, so presence is precisely "enabled"; a configured-but-disabled
  remote is detected via `--show-disabled`.
- **Fallback (config files):** only when flatpak is absent or every remote-list
  call fails. Probe `${_FLATHUB_SYSTEM_CONFIG:-/var/lib/flatpak/repo/config}`
  and `${_FLATHUB_USER_CONFIG:-${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/repo/config}`
  for a `[remote "flathub"]` section; present = configured, enabled unless an
  `enabled=false` key is in that section. Paths are env-overridable for tests
  (mirrors `detect-os.sh`'s `_OS_ROOT` hook). Pure bash parser — no grep/sed/awk.
- A successful "remote-list answered, no flathub" is authoritative
  not-configured; the file fallback never second-guesses it.

## Multi-distro

Command-first is deliberate: flatpak resolves the actual system-installation
layout itself, so the same code is correct on Fedora/Debian/Arch/Mint/Pop!_OS
and for both pre-enabled and manually-added flathub. `--columns=name` output
is locale-stable. No root/sudo is required for detection. Limitations
documented: additional `--installation=` remotes and hidden remotes are out of
scope.

## Contract

| Function | stdout | rc |
|---|---|---|
| `flathub_detect` | (nothing) | `0` enabled / `1` not enabled; writes globals; **re-runs fresh every call** |
| `flathub_enabled` | (nothing) — guard | `0` iff enabled; lazy |
| `flathub_state` | `enabled`/`disabled`/`not-configured`/`flatpak-missing` | `0` always; lazy |
| `flathub_scope` | `system`/`user`/`both`/empty | `0` always; lazy |

Globals: `FLATHUB_ENABLED` (1/0), `FLATHUB_CONFIGURED` (1/0), `FLATHUB_STATE`,
`FLATHUB_SCOPE`, `FLATHUB_BIN`.
Internal: `_FLATHUB_DETECTED` (guard), `_FLATHUB_DETECT_SOURCED` (double-source).

## Lazy caching

Accessors call `_flathub_ensure`, which runs `flathub_detect` at most once per
shell (`_FLATHUB_DETECTED` guard). Consumers have **no ordering requirement**
and repeated concurrent accessor calls never re-run detection. `flathub_detect`
itself always re-detects — an explicit refresh escape hatch.

## Safety

Strict-mode safe (`set -euo pipefail`): all command substitutions guarded
(`$(...) || rc=$?` / `|| true`), all expansions quoted, accessors guard
`flathub_detect` with `|| true`, robust `${HOME:-}` handling in the user-config
path. No `set -e`/traps/temp files leaked into caller. Double-source no-op;
direct execution exits 2 with a "source-only" hint (mirrors siblings).

## Files

```
fx-flathub-detect.sh          # library
README.md                  # sibling README style
docs/cheatsheet.md         # run/debug reference
docs/superpowers/specs/    # this doc
test/flathub_detect.bats   # bats-core suite
```

## Testing

bats suite with a fixture `bin/flatpak` on a controlled PATH (env-driven
remote names per scope) plus env-overridden repo config fixtures for the file
fallback. Covers: double-source, enabled in system/user/both (+scope), disabled
via `--show-disabled`, not-configured, longer-name false-positive guard, flatpak
missing, config-fallback system/user/both, `enabled=false` → disabled, no-config
→ flatpak-missing, lazy single-detection, explicit refresh, strict-mode caller,
`set -u` safety, direct-exec Exit 2. Lint: `bash -n`, `shellcheck -S style`.