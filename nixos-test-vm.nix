{ config, pkgs, lib, ... }:

{
  # NixOS VM configuration for testing flathub-detect with custom installation
  # qemu-vm module imported via flake.nix using nixosModules

  # System
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = false;
  boot.kernelParams = [ "console=ttyS0" ];

  # Network
  networking = {
    hostName = "flathub-test";
    firewall.enable = false;
  };

  # SSH for testing
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = "yes";
    };
  };

  # Root user with password
  users.users.root = {
    password = "test";
    openssh.authorizedKeys.keys = [];
  };

  # Flatpak with custom installation (manual setup - extraInstallations option not available in nixos-unstable)
  services.flatpak.enable = true;

  # System packages
  environment.systemPackages = with pkgs; [
    flatpak
    bash
    curl
    gnugrep
    gnused
  ];

  # Add flathub remote to custom installation on first boot
  systemd.services.flathub-setup = {
    description = "Setup Flathub remote in custom installation";
    after = [ "flatpak.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/bin/bash -c 'mkdir -p /var/lib/flatpak/extra && flatpak --installation=extra remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo'";
    };
  };

  # Auto-login for root on serial console
  systemd.services."getty@ttyS0" = {
    override = {
      Service = {
        ExecStart = "/sbin/agetty --autologin root --noclear %I $TERM";
      };
    };
  };

  # VM image (qemu-vm module options)
  virtualisation.vmVariant = "qemu";
  virtualisation.memorySize = 1024;
  virtualisation.cores = 2;
  virtualisation.diskSize = 8192;
}