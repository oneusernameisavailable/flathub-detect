# fx-flathub-detect.sh — Flathub repository enabled-detection library

A source-only bash library that tells other build scripts whether the *Flathub*
remote is **enabled** in a Flatpak installation on this system, plus where
(system/user) and in what state. Sourced by other scripts ("subsequent scripts
are **bash**"). Safe under caller strict mode (`set -euo pipefail`).
Distro-agnostic by design: detection goes through flatpak's own
`remote-list` interface, so whatever system-installation layout a distro chose
resolves identically, and **no root/sudo is required** for detection.

```sh
. "$(dirname "$0")/fx-flathub-detect.sh"
if flathub_enabled; then
    printf 'flathub is %s (scope: %s)\n' "$(flathub_state)" "$(flathub_scope)"
fi
```

> **No ordering requirement.** Accessors are *lazy*: the first call runs
> detection once and every later call in the same shell answers from memory.
> There is no "call `flathub_detect` first" footgun, and repeated accessor
> calls never re-run detection.

---

## API contract

| Function          | stdout                        | rc                                            |
| ----------------- | ----------------------------- | --------------------------------------------- |
| `flathub_detect`  | (nothing)                     | `0` enabled, `1` not enabled (globals still written) |
| `flathub_enabled` | (nothing) — use as guard      | `0` iff enabled (lazy)                        |
| `flathub_state`   | `enabled` / `disabled` / `not-configured` / `unknown` / `flatpak-missing` / `unreachable` | `0` always |
| `flathub_scope`   | `system` / `user` / `both` / empty / `<installation>` / `<comma-separated>` | `0` always |

Globals (raw storage, not the stable interface): `FLATHUB_ENABLED` (1/0),
`FLATHUB_CONFIGURED` (1/0 = remote present at all, enabled or not),
`FLATHUB_STATE`, `FLATHUB_SCOPE`, `FLATHUB_BIN` (flatpak binary path when
found). `_FLATHUB_DETECTED` and `_FLATHUB_DETECT_SOURCED` are internal and
should not be read or written.

Exit codes outside the API:
- script sourced a second time → no-op, rc `0` (double-source guard)
- executed directly (`bash fx-flathub-detect.sh`) → usage hint on stderr, **exit 2**

---

## Semantics — what "enabled" means

"Enabled" = the Flathub remote is enabled in **any** installation (system **or**
user **or** custom `--installation`). `flathub_scope` narrows it down.

| Condition                                                | Result                                  |
| -------------------------------------------------------- | --------------------------------------- |
| `flatpak remote-list --system/--user --columns=name` lists exact `flathub` | enabled (`FLATHUB_ENABLED=1`, `FLATHUB_STATE=enabled`) |
| `flatpak remote-list --installation=NAME --columns=name` lists exact `flathub` | enabled (`FLATHUB_ENABLED=1`, `FLATHUB_STATE=enabled`) |
| listed only under `--show-disabled`                      | configured but disabled (`FLATHUB_CONFIGURED=1`, `FLATHUB_STATE=disabled`) |
| remote-list answers, no `flathub` anywhere               | not configured (`FLATHUB_STATE=not-configured`) |
| any required query fails or fallback is malformed       | unknown (fail closed) |
| no `flatpak` on `PATH` and no repo config found          | `FLATHUB_STATE=flatpak-missing`          |
| `flatpak` absent/unresponsive, but repo config has `[remote "flathub"]` (no `enabled=false`) | enabled via config fallback |
| `FLATHUB_PROBE_REACHABILITY=1` and remote configured but network unreachable | `FLATHUB_STATE=unreachable` |

The predicate uses `type -P flatpak` (a bash builtin) for the binary-presence
gate, exactly like the sibling `flatpak-detect.sh`. Remote state is read from
`flatpak remote-list --columns=name`, which hides disabled remotes — so an
exact, whole-line `flathub` match means **enabled**, and `--show-disabled` is
consulted only to distinguish "disabled" from "not configured". The raw-config
fallback (freedesktop-standard paths) is used **only** when flatpak is absent
or every remote-list call fails — a successful "no flathub here" answer is
authoritative and is never second-guessed with a possibly-stale file.

Every external command is `||`-guarded and the config parser is pure bash (no
`grep`/`sed`/`awk`), keeping the library safe inside `set -e` callers.

### Multi-distro notes

- The command path is the cross-distro authority: flatpak resolves "the
  system installation" itself (default dirs, `/etc/flatpak/installations.d`,
  custom installation dirs), so it works identically on Fedora/Debian/Arch/
  Mint/Pop!_OS and for both pre-enabled and manually-added flathub.
- System and user scopes are both checked, so both `sudo flatpak install` (root,
  system) and plain-user installs are covered.
- Custom installations defined in `/etc/flatpak/installations.d/*.conf` are
  automatically probed (e.g., Fedora Silverblue, Steam Deck).
- The config-file fallback covers the freedesktop-standard paths only
  (`/var/lib/flatpak/repo/config`, `${XDG_DATA_HOME:=$HOME/.local/share}/flatpak/repo/config`).
- **Limitations:** admin-hidden remotes are intentionally out of scope.

---

## Lazy caching & refresh

- `flathub_enabled` / `flathub_state` / `flathub_scope` run the detection at
  most **once per shell** (backed by the `_FLATHUB_DETECTED` guard), then
  answer from memory.
- `flathub_detect` **always re-detects** — call it explicitly to refresh after
  a change (e.g. `flatpak remote-add` / `remote-modify --disable` earlier in
  the same script).

```sh
. "$(dirname "$0")/fx-flathub-detect.sh"
flathub_enabled && echo "state: $(flathub_state)"
# flathub got added/disabled in the meantime...
flathub_detect && echo "now enabled: $(flathub_scope)"
```

---

## Environment hooks

| Variable | Effect |
| --- | --- |
| `_FLATHUB_DEBUG` / `SCRIPT_DEBUG` | set to `1` to trace detection steps to stderr. Evaluated **per call**, so it can be turned on mid-session, after sourcing. |
| `_FLATHUB_SYSTEM_CONFIG` / `_FLATHUB_USER_CONFIG` | override the config-file fallback paths (test/chroot hook, mirrors `detect-os.sh`'s `_OS_ROOT`). |
| `_FLATHUB_PINNED_FLATPAK` | internal consumer hook for a validated absolute binary path |

---

## Consumer patterns

Add flathub only when it isn't enabled:

```sh
. "$(dirname "$0")/fx-flathub-detect.sh"
if ! flathub_enabled; then
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi
```

Explain *why* an install may fail, per the actual state:

```sh
case "$(flathub_state)" in
    flatpak-missing) echo "install flatpak first" ;;
    disabled)        echo "enable the flathub remote, then retry" ;;
    not-configured)  sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo ;;
    enabled)         : ;;
esac
```

---

## Repository layout & validation

```
fx-flathub-detect.sh          # the library (source-only)
README.md                  # this file
docs/cheatsheet.md         # quick run/debug reference
docs/superpowers/specs/    # design doc
test/flathub_detect.bats   # bats-core integration suite
```

```sh
bats test/flathub_detect.bats                     # 18 tests
shellcheck -S style -x fx-flathub-detect.sh test/flathub_detect.bats
bash -n fx-flathub-detect.sh
```

Tooling (Arch/CachyOS): `sudo pacman -S bats-core shellcheck`.