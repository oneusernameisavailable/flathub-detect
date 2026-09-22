# CI Matrix Specification for fx-flathub-detect.sh

## Goal
Validate detection accuracy across Flatpak versions, distros, and edge cases before production sign-off.

---

## Test Matrix

| Dimension | Values | Rationale |
|-----------|--------|-----------|
| **Flatpak Version** | 1.10, 1.12, 1.14, 1.15, 1.18 | `--columns=name` added in 1.10; output format changes across versions |
| **Distro/Base** | Fedora 40/41 (Workstation, Silverblue, Kinoite), RHEL 9/10, Rocky/Alma 9/10, CentOS Stream 9/10, Ubuntu 20.04/22.04/24.04, Debian 11/12, Arch (rolling), Manjaro, EndeavourOS, NixOS 24.05/24.11, openSUSE Tumbleweed/Leap 15.6, SLES 15 SP6, Alpine 3.19/3.20, Gentoo, Void, Clear Linux, Solus, Pop!_OS 22.04, Linux Mint 21/22, elementary OS 7/8, Zorin OS 17, Steam Deck (Jupiter), Endless OS, ChromeOS (Crostini), WSL2 (Ubuntu/Debian/Arch), macOS (Homebrew/MacPorts) | Covers rpm, deb, pacman, nix, apk, eopkg, xbps, portage, swupd package managers; immutable (OSTree, rpm-ostree, A/B) vs mutable roots; atomic vs traditional updates; container/VM hosts |
| **Installation Type** | System-only, User-only, Both, System+User+Custom (`--installation=extra`) | Tests scope aggregation and custom installation blind spot |
| **SELinux/AppArmor** | Enforcing, Permissive, Disabled | `flatpak remote-list --system` fails under enforcing without flatpak group |
| **Flatpak Source** | Distro package, Flatpak-bundled, Flathub-beta remote | Different binary paths and config layouts |
| **Filesystem** | ext4, btrfs, xfs, zfs, nfs (1s mtime granularity), overlayfs | Cache fingerprint mtime:size behavior |

**Total combinations**: 5 × 7 × 4 × 3 × 3 × 3 = **3,780** (too many) → **stratified sampling below**

---

## Stratified Sampling (80% Coverage, ~120 Runs)

| # | Flatpak | Distro Family | Distro Variant | Installation | SELinux | Source | FS | Priority |
|---|---------|---------------|----------------|--------------|---------|--------|----|----------|
| 1 | 1.18 | Fedora (rpm-ostree) | Fedora 41 Silverblue | System+User | Enforcing | Distro | btrfs | CRITICAL |
| 2 | 1.18 | Fedora (rpm-ostree) | Fedora 41 Kinoite | System+User | Enforcing | Distro | btrfs | CRITICAL |
| 3 | 1.18 | Fedora (traditional) | Fedora 41 Workstation | System+User | Enforcing | Distro | btrfs | CRITICAL |
| 4 | 1.18 | RHEL-family | RHEL 10 | System | Enforcing | Distro | xfs | CRITICAL |
| 5 | 1.18 | RHEL-family | Rocky Linux 9 | System | Enforcing | Distro | xfs | HIGH |
| 6 | 1.18 | RHEL-family | AlmaLinux 9 | System | Enforcing | Distro | ext4 | HIGH |
| 7 | 1.18 | RHEL-family | CentOS Stream 10 | System | Enforcing | Distro | xfs | HIGH |
| 8 | 1.18 | Debian-family | Ubuntu 24.04 | System+User | AppArmor | Distro | ext4 | CRITICAL |
| 9 | 1.18 | Debian-family | Ubuntu 22.04 LTS | System+User | AppArmor | Distro | ext4 | HIGH |
| 10 | 1.18 | Debian-family | Ubuntu 20.04 LTS | System | AppArmor | Distro | ext4 | MEDIUM |
| 11 | 1.18 | Debian-family | Debian 12 | System | Disabled | Distro | ext4 | HIGH |
| 12 | 1.18 | Debian-family | Debian 11 LTS | System | Disabled | Distro | ext4 | MEDIUM |
| 13 | 1.18 | Debian-family | Pop!_OS 22.04 | System+User | AppArmor | Distro | ext4 | HIGH |
| 14 | 1.18 | Debian-family | Linux Mint 22 | System+User | AppArmor | Distro | ext4 | MEDIUM |
| 15 | 1.18 | Debian-family | elementary OS 8 | System+User | AppArmor | Distro | ext4 | MEDIUM |
| 16 | 1.18 | Debian-family | Zorin OS 17 | System+User | AppArmor | Distro | ext4 | MEDIUM |
| 17 | 1.18 | Arch-family | Arch Linux (rolling) | System+User | Disabled | Distro | btrfs | CRITICAL |
| 18 | 1.18 | Arch-family | Manjaro Stable | System+User | Disabled | Distro | ext4 | HIGH |
| 19 | 1.18 | Arch-family | EndeavourOS | System+User | Disabled | Distro | btrfs | MEDIUM |
| 20 | 1.18 | NixOS | NixOS 24.11 | System+User+Custom | Disabled | Nixpkgs | zfs | CRITICAL |
| 21 | 1.18 | NixOS | NixOS 24.05 LTS | System+User+Custom | Disabled | Nixpkgs | zfs | HIGH |
| 22 | 1.18 | openSUSE | openSUSE Tumbleweed | System | Disabled | Distro | btrfs | HIGH |
| 23 | 1.18 | openSUSE | openSUSE Leap 15.6 | System | Disabled | Distro | ext4 | MEDIUM |
| 24 | 1.18 | SUSE | SLES 15 SP6 | System | Enforcing | Distro | xfs | MEDIUM |
| 25 | 1.18 | Alpine | Alpine 3.20 | User-only | Disabled | Distro | overlayfs | HIGH |
| 26 | 1.18 | Alpine | Alpine 3.19 | User-only | Disabled | Distro | overlayfs | MEDIUM |
| 27 | 1.18 | Gentoo | Gentoo (rolling) | System+User | Disabled | Distro | ext4 | MEDIUM |
| 28 | 1.18 | Void | Void Linux | System+User | Disabled | Distro | btrfs | MEDIUM |
| 29 | 1.18 | Clear Linux | Clear Linux | System | Disabled | Distro | ext4 | MEDIUM |
| 30 | 1.18 | Solus | Solus 4.5 | System+User | Disabled | Distro | btrfs | MEDIUM |
| 31 | 1.18 | Immutable/OSTree | Endless OS | System+User | Disabled | Distro | ostree | CRITICAL |
| 32 | 1.18 | Immutable/OSTree | Steam Deck (Jupiter) | System+User | Enforcing | Distro | btrfs | CRITICAL |
| 33 | 1.18 | Immutable/OSTree | Fedora IoT / CoreOS | System | Enforcing | Distro | ext4 | HIGH |
| 34 | 1.18 | ChromeOS | ChromeOS (Crostini) | User | N/A | Distro | ext4 | HIGH |
| 35 | 1.18 | WSL2 | Ubuntu 24.04 | User | N/A | Distro | ext4 | HIGH |
| 36 | 1.18 | WSL2 | Debian 12 | User | N/A | Distro | ext4 | MEDIUM |
| 37 | 1.18 | WSL2 | Arch | User | N/A | Distro | ext4 | MEDIUM |
| 38 | 1.18 | macOS | macOS 15 (Sequoia) | User-only | N/A | Homebrew | apfs | CRITICAL |
| 39 | 1.18 | macOS | macOS 14 (Sonoma) | User-only | N/A | MacPorts | apfs | MEDIUM |
| 40 | 1.15 | Fedora | Fedora 40 Workstation | System | Enforcing | Flathub-beta | ext4 | HIGH |
| 41 | 1.15 | Ubuntu | Ubuntu 22.04 | System+User | AppArmor | Flatpak-bundled | ext4 | MEDIUM |
| 42 | 1.14 | openSUSE | openSUSE Tumbleweed | System | Disabled | Distro | btrfs | MEDIUM |
| 43 | 1.12 | Debian | Debian 11 LTS | System | Disabled | Distro | ext4 | MEDIUM |
| 43 | 1.10 | Alpine | Alpine 3.19 | User-only | Disabled | Distro | overlayfs | MEDIUM |

**Flatpak Version Coverage**: 1.18 (32 rows), 1.15 (2), 1.14 (1), 1.12 (1), 1.10 (1) = **37 distro variants × 5 versions ≈ 185 test points**

---

## Extended Distro Family Coverage Notes

### RHEL Family (rpm + SELinux)
| Distro | Notes |
|--------|-------|
| RHEL 9/10 | Subscription required; use UBI for CI |
| Rocky Linux 9/10 | 1:1 RHEL rebuild; free |
| AlmaLinux 9/10 | 1:1 RHEL rebuild; free |
| CentOS Stream 9/10 | Upstream of RHEL; free |
| Oracle Linux 9/10 | UEK kernel; Ksplice |
| EuroLinux 9/10 | Polish rebuild |
| Miracle Linux 9 | Japanese rebuild |

### Debian Family (deb + AppArmor)
| Distro | Base | Notes |
|--------|------|-------|
| Ubuntu 24.04/22.04/20.04 | Debian Sid/Testing/Stable | Snap integration may affect flatpak paths |
| Debian 12/11 | — | Pure deb; no Snap |
| Pop!_OS 22.04 | Ubuntu 22.04 | COSMIC DE; custom flatpak repo |
| Linux Mint 22/21 | Ubuntu LTS | mintinstall backend uses flatpak |
| elementary OS 8/7 | Ubuntu LTS | AppCenter uses flatpak |
| Zorin OS 17/16 | Ubuntu LTS | Windows-like UX |
| KDE Neon 24.04/22.04 | Ubuntu LTS | KDE Flatpak integration |
| MX Linux 23/21 | Debian Stable | AntiX-based |
| Kali Linux 2024 | Debian Testing | Security-focused |
| Deepin 23 | Debian Stable | Chinese DE |

### Arch Family (pacman)
| Distro | Notes |
|--------|-------|
| Arch Linux | Rolling; latest flatpak |
| Manjaro Stable/Testing/Unstable | Held-back packages; may lag flatpak |
| EndeavourOS | Close to Arch |
| Garuda Linux | Gaming-focused; btrfs default |
| ArcoLinux | Learning-oriented |
| Artix Linux | No systemd; runit/s6/openrc |

### NixOS (nixpkgs)
| Channel | Notes |
|---------|-------|
| nixos-24.11 | Latest |
| nixos-24.05 | LTS |
| nixos-unstable | Bleeding edge |
| nixpkgs (non-NixOS) | Nix on other distros |

### SUSE Family (rpm + AppArmor)
| Distro | Notes |
|--------|-------|
| openSUSE Tumbleweed | Rolling; latest flatpak |
| openSUSE Leap 15.6 | Stable; older flatpak |
| SLES 15 SP6 | Enterprise; subscription |
| openSUSE MicroOS | Immutable; rpm-ostree |
| openSUSE Aeon | Desktop MicroOS |

### Immutable/OSTree Distros
| Distro | Tech | Notes |
|--------|------|-------|
| Fedora Silverblue/Kinoite | rpm-ostree | A/B root; layered packages |
| Fedora CoreOS/IoT | rpm-ostree | Server/edge |
| Endless OS | OSTree + Flatpak | Consumer-focused |
| Steam Deck (Jupiter) | Arch + OSTree | Gaming handheld |
| Vanilla OS | Ubuntu + OSTree | ABRoot |
| Nitrux | Debian + znx | AppImage-first |
| BlendOS | Arch + OSTree | Multi-distro container |

### Container/VM Environments
| Env | Notes |
|-----|-------|
| ChromeOS Crostini | Debian container; user-only flatpak |
| WSL2 Ubuntu/Debian/Arch | systemd support; user scope primary |
| Podman/Docker containers | Rootless; no system flatpak |
| distrobox/toolbx | Containerized dev envs |

### macOS
| Source | Path | Notes |
|--------|------|-------|
| Homebrew (ARM) | `/opt/homebrew` | Apple Silicon default |
| Homebrew (Intel) | `/usr/local` | x86_64 legacy |
| MacPorts | `/opt/local` | Alternative |
| Flatpak-bundled | App bundle | Some apps bundle flatpak |

---

## Test Harness Requirements

### Per-Platform Validation Script
```bash
#!/usr/bin/env bash
# validate-detection.sh — run inside each CI container/VM

set -euo pipefail

LIB_PATH="/path/to/fx-flathub-detect.sh"
SCENARIO="$1"  # e.g., "enabled-system", "disabled-user", "custom-installation"

source "$LIB_PATH"

case "$SCENARIO" in
    enabled-system)
        # Verify: flathub_enabled=true, scope=system, state=enabled
        flathub_enabled && [[ "$FLATHUB_SCOPE" == "system" ]] && [[ "$FLATHUB_STATE" == "enabled" ]]
        ;;
    disabled-user)
        # Verify: flathub_enabled=false, state=disabled
        ! flathub_enabled && [[ "$FLATHUB_STATE" == "disabled" ]]
        ;;
    not-configured)
        # Verify: flathub_enabled=false, state=not-configured, scope=empty
        ! flathub_enabled && [[ "$FLATHUB_STATE" == "not-configured" ]] && [[ "$FLATHUB_SCOPE" == "empty" ]]
        ;;
    custom-installation)
        # Verify: detects flathub in /var/lib/flatpak/installations.d/extra.conf
        flathub_enabled && [[ "$FLATHUB_SCOPES_JSON" =~ "installation" ]]
        ;;
    flatpak-missing)
        # Verify: flatpak binary absent, state=flatpak-missing
        ! flathub_enabled && [[ "$FLATHUB_STATE" == "flatpak-missing" ]]
        ;;
    reachability-probe)
        # Verify: binary exists but remote-list fails -> fallback triggers
        # (requires mock or network isolation)
        ;;
esac
```

### CI Pipeline (GitHub Actions Example)
```yaml
name: Flathub Detection Matrix
on: [push, pull_request, schedule]

jobs:
  matrix:
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        include:
          # CRITICAL - Fedora rpm-ostree (immutable)
          - { os: ubuntu-latest, distro: fedora:41, variant: silverblue, flatpak: 1.18, scenario: enabled-system, selinux: enforcing }
          - { os: ubuntu-latest, distro: fedora:41, variant: kinoite, flatpak: 1.18, scenario: enabled-system, selinux: enforcing }
          - { os: ubuntu-latest, distro: fedora:41, variant: workstation, flatpak: 1.18, scenario: enabled-system, selinux: enforcing }
          - { os: ubuntu-latest, distro: quay.io/fedora/fedora:41, flatpak: 1.18, scenario: custom-installation, selinux: enforcing }

          # CRITICAL - RHEL family
          - { os: ubuntu-latest, distro: rockylinux/rockylinux:9, flatpak: 1.18, scenario: enabled-system, selinux: enforcing }
          - { os: ubuntu-latest, distro: almalinux/almalinux:9, flatpak: 1.18, scenario: enabled-system, selinux: enforcing }
          - { os: ubuntu-latest, distro: centos/centos:stream10, flatpak: 1.18, scenario: enabled-system, selinux: enforcing }

          # CRITICAL - Debian/Ubuntu family
          - { os: ubuntu-latest, distro: ubuntu:24.04, flatpak: 1.18, scenario: enabled-system, apparmor: true }
          - { os: ubuntu-latest, distro: ubuntu:22.04, flatpak: 1.18, scenario: enabled-system, apparmor: true }
          - { os: ubuntu-latest, distro: debian:12, flatpak: 1.18, scenario: enabled-system }
          - { os: ubuntu-latest, distro: pop-os/pop-os:22.04, flatpak: 1.18, scenario: enabled-system, apparmor: true }
          - { os: ubuntu-latest, distro: linuxmint/mint:22, flatpak: 1.18, scenario: enabled-system, apparmor: true }

          # CRITICAL - Arch family
          - { os: ubuntu-latest, distro: archlinux/archlinux:latest, flatpak: 1.18, scenario: enabled-system }
          - { os: ubuntu-latest, distro: manjarolinux/manjaro:stable, flatpak: 1.18, scenario: enabled-system }

          # CRITICAL - NixOS (immutable, custom paths)
          - { os: ubuntu-latest, distro: nixos/nixos:24.11, flatpak: 1.18, scenario: custom-installation }

          # CRITICAL - Immutable/OSTree
          - { os: ubuntu-latest, distro: endlessm/endless:latest, flatpak: 1.18, scenario: enabled-system }
          - { os: ubuntu-latest, distro: valvedev/steamos:jupiter, flatpak: 1.18, scenario: enabled-system, selinux: enforcing }

          # CRITICAL - macOS
          - { os: macos-latest, distro: macos, flatpak: 1.18, scenario: enabled-user }

          # HIGH - Extended coverage
          - { os: ubuntu-latest, distro: opensuse/tumbleweed:latest, flatpak: 1.18, scenario: enabled-system }
          - { os: ubuntu-latest, distro: alpine:3.20, flatpak: 1.18, scenario: enabled-user }
          - { os: ubuntu-latest, distro: clearos/clear:latest, flatpak: 1.18, scenario: enabled-system }
          - { os: ubuntu-latest, distro: solus/solus:4.5, flatpak: 1.18, scenario: enabled-system }
          - { os: ubuntu-latest, distro: voidlinux/void:latest, flatpak: 1.18, scenario: enabled-system }
          - { os: ubuntu-latest, distro: gentoo/stage3:latest, flatpak: 1.18, scenario: enabled-system }
          - { os: ubuntu-latest, distro: chromeos/crostini:latest, flatpak: 1.18, scenario: enabled-user }
          - { os: ubuntu-latest, distro: mcr.microsoft.com/devcontainers/base:ubuntu-24.04, flatpak: 1.18, scenario: enabled-user }  # WSL2 proxy
          - { os: ubuntu-latest, distro: mcr.microsoft.com/devcontainers/base:debian-12, flatpak: 1.18, scenario: enabled-user }
          - { os: ubuntu-latest, distro: mcr.microsoft.com/devcontainers/base:arch, flatpak: 1.18, scenario: enabled-user }

          # MEDIUM - Version regression
          - { os: ubuntu-latest, distro: fedora:40, flatpak: 1.15, scenario: enabled-system, selinux: enforcing }
          - { os: ubuntu-latest, distro: ubuntu:22.04, flatpak: 1.15, scenario: enabled-system, apparmor: true }
          - { os: ubuntu-latest, distro: opensuse/tumbleweed:latest, flatpak: 1.14, scenario: enabled-system }
          - { os: ubuntu-latest, distro: debian:11, flatpak: 1.12, scenario: enabled-system }
          - { os: ubuntu-latest, distro: alpine:3.19, flatpak: 1.10, scenario: enabled-user }
          - { os: macos-13, distro: macos, flatpak: 1.18, scenario: enabled-user }  # macOS 14 Sonoma
    steps:
      - uses: actions/checkout@v4
      - name: Run validation
        run: |
          docker run --rm --privileged \
            -v ${{ github.workspace }}:/src \
            ${{ matrix.distro }}${{ matrix.variant && ':' || '' }}${{ matrix.variant || '' }} \
            /src/test/ci/validate-detection.sh ${{ matrix.scenario }} ${{ matrix.selinux || '' }} ${{ matrix.apparmor || '' }}
```

---

## Regression Test Scenarios (Per Matrix Run)

| Scenario | Precondition | Expected State | Scope | Notes |
|----------|--------------|----------------|-------|-------|
| `enabled-system` | `flatpak remote-add --system flathub ...` | enabled | system | |
| `enabled-user` | `flatpak remote-add --user flathub ...` | enabled | user | |
| `enabled-both` | Both above | enabled | both | |
| `disabled-system` | `flatpak remote-modify --system --disable flathub` | disabled | system | |
| `disabled-user` | `flatpak remote-modify --user --disable flathub` | disabled | user | |
| `not-configured` | No flathub remote | not-configured | empty | |
| `flatpak-missing` | No flatpak binary | flatpak-missing | empty | |
| `custom-installation` | `/etc/flatpak/installations.d/extra.conf` with flathub | enabled | installation (if supported) | **Known limitation** |
| `partial-failure-system` | System scope query fails (SELinux), user works | not-configured | user | **Regression: must not return unknown** |
| `reachability-probe` | Binary exists, `remote-list` fails (network) | unknown/fallback | per fallback | **New feature** |
| `stale-cache` | Config changed externally, mtime same second | Re-detects | N/A | **Cache integrity** |
| `toctou-symlink` | Symlink swap during read | Rejects or consistent | N/A | **Security** |

---

## Acceptance Criteria

| Metric | Threshold |
|--------|-----------|
| All CRITICAL scenarios pass | 100% |
| All HIGH scenarios pass | 100% |
| MEDIUM scenarios pass | ≥90% |
| No false `enabled` on disabled/not-configured | 0 |
| No `unknown` when authoritative answer exists | 0 |
| Cache invalidation on config change | ≤1s detection |
| No shell crashes on any scenario | 0 |

---

## Automation Notes

### Container Images for CI
```bash
# Fedora family
fedora:41                    # Workstation
fedora:41-silverblue         # rpm-ostree immutable
fedora:41-kinoite            # KDE rpm-ostree
rockylinux/rockylinux:9      # RHEL rebuild
almalinux/almalinux:9        # RHEL rebuild
centos/centos:stream10       # CentOS Stream

# Debian/Ubuntu family
ubuntu:24.04                 # Noble
ubuntu:22.04                 # Jammy LTS
ubuntu:20.04                 # Focal LTS
debian:12                    # Bookworm
debian:11                    # Bullseye LTS
pop-os/pop-os:22.04          # System76
linuxmint/mint:22            # Mint

# Arch family
archlinux/archlinux:latest   # Rolling
manjarolinux/manjaro:stable  # Held-back

# NixOS
nixos/nixos:24.11            # Latest
nixos/nixos:24.05            # LTS

# SUSE
opensuse/tumbleweed:latest   # Rolling
opensuse/leap:15.6           # Stable

# Alpine
alpine:3.20                  # Latest
alpine:3.19                  # Previous

# Immutable/OSTree
endlessm/endless:latest      # Endless OS
valvedev/steamos:jupiter     # Steam Deck

# Other
clearos/clear:latest         # Clear Linux
solus/solus:4.5              # Solus
voidlinux/void:latest        # Void
gentoo/stage3:latest         # Gentoo
```

### Special Handling
| Distro | Method | Notes |
|--------|--------|-------|
| Fedora Silverblue/Kinoite | `podman run --privileged --pid=host` | rpm-ostree needs host access |
| NixOS | `nixos-generators` → VM | `/nix/store` paths unique |
| Steam Deck | QEMU-KVM + Jupiter image | Hardware-specific; document gaps |
| Endless OS | QEMU + OSTree image | Consumer OSTree |
| ChromeOS Crostini | `crosvm` or container | Nested virtualization |
| WSL2 | Microsoft devcontainers | `systemd=true` in `.devcontainer` |
| macOS | GitHub Actions `macos-latest` | Native runner; Homebrew preinstalled |
| Clear Linux | `clearos/clear:latest` | `swupd` bundle system |

### CI Caching Strategy
```yaml
- name: Cache Flatpak bundles
  uses: actions/cache@v4
  with:
    path: |
      ~/.cache/flatpak
      /var/lib/flatpak
    key: flatpak-${{ matrix.distro }}-${{ matrix.flatpak }}-${{ hashFiles('**/Dockerfile') }}
```

### Parallelism
- **43 distro variants × 5 Flatpak versions = 215 test points**
- Run in batches of 20-30 parallel jobs
- Estimated CI time: 45-60 min full matrix
- Schedule: nightly full, PR changed-only subset

---

## Timeline

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| Harness + 15 CRITICAL platforms | 1.5 weeks | Core immutable + major family coverage |
| Add 15 HIGH platforms | 1 week | RHEL, Debian, Arch, NixOS, macOS depth |
| Add 13 MEDIUM platforms | 1 week | Extended family coverage |
| Version regression (5 versions × 3 distros) | 3 days | 1.10, 1.12, 1.14, 1.15, 1.18 |
| Flakiness elimination & docs | 3 days | Stable CI, README updates |
| **Total** | **~4.5 weeks** | **Production-ready matrix** |