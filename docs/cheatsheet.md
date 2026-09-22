# fx-flathub-detect.sh — run / debug cheatsheet

```
. ./fx-flathub-detect.sh        # define functions (no side effects)
if flathub_enabled; then     # lazy: detects once, cached for the session
    echo "state $(flathub_state) @ scope $(flathub_scope)"
fi
```

## API in one glance

| Call                | Question it answers                       | rc  |
| ------------------- | ----------------------------------------- | --- |
| `flathub_detect`    | re-run detection fresh                    | 0/1 |
| `flathub_enabled`   | flathub enabled anywhere? (guard)         | 0/1 |
| `flathub_state`     | `enabled`/`disabled`/`not-configured`/`unknown`/`flatpak-missing` | 0 |
| `flathub_scope`     | `system`/`user`/`both`/empty               | 0   |

`flathub_state` / `flathub_scope` echo **empty** only for scope when nothing
was found, so they never trip `set -u`.

## Semantics

- Enabled = exact `flathub` line in `flatpak remote-list --system/--user
  --columns=name`. `remote-list` hides disabled remotes, so presence = enabled.
- Disabled = listed only via `--show-disabled` (configured but not enabled).
- Config-file fallback (`/var/lib/flatpak/repo/config`,
  `~/.local/share/flatpak/repo/config`) only when flatpak is absent or every
  remote-list call fails; section `[remote "flathub"]` = configured, enabled
  unless `enabled=false`.
- **No sudo needed.** Detection is unprivileged on every distro.
- Accessors cache: first call detects, later calls answer from memory. Call
  `flathub_detect` explicitly to refresh (e.g. after `remote-add` /
  `remote-modify --disable`).
- Partial command failures and malformed fallback values produce `unknown`,
  never `not-configured`; callers should fail closed.

## Globals

`FLATHUB_ENABLED FLATHUB_CONFIGURED FLATHUB_STATE FLATHUB_SCOPE FLATHUB_BIN`

Internal (do not touch): `_FLATHUB_DETECTED` (lazy-cache guard),
`_FLATHUB_DETECT_SOURCED` (double-source guard).

## Debug

```
export _FLATHUB_DEBUG=1       # or SCRIPT_DEBUG=1
if flathub_enabled; then ... fi
```

Trace lines go to stderr with a `fx-flathub-detect:` prefix. Enabled/disabled per
call, so it can be toggled mid-session.

## Testing with a fixture fake

The command path only consults `PATH` + fixture env, so a fake binary stands in
for the real one — no root, no host mutation:

```
fake_bin="$PWD/fakebin"; mkdir -p "$fake_bin"
cat > "$fake_bin/flatpak" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --system "*) list="${RL_SYSTEM:-}" ;; *" --user "*) list="${RL_USER:-}" ;; esac
for n in $list; do printf '%s\n' "$n"; done
EOF
chmod +x "$fake_bin/flatpak"
RL_SYSTEM=flathub PATH="$fake_bin:$PATH" bash -c '. ./fx-flathub-detect.sh; flathub_enabled && flathub_scope'
# -> system
```

Config-fallback tests override the probe paths instead:

```
export _FLATHUB_SYSTEM_CONFIG="$PWD/sys-config" _FLATHUB_USER_CONFIG="$PWD/user-config"
```

bats suite: `test/flathub_detect.bats` (needs
[bats-core](https://bats-core.github.io/)).

## Lint / syntax

```
bash -n fx-flathub-detect.sh
shellcheck -S style fx-flathub-detect.sh   # if shellcheck installed
```