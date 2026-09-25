{ config, pkgs, lib, ... }:
{
  # NixOS VM configuration for testing flathub-detect with custom installation
  # qemu-vm module imported via flake.nix

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
      PasswordAuthentication = true;
    };
  };

  # Root user with password
  users.users.root = {
    password = "test";
    openssh.authorizedKeys.keys = [];
  };

  # Flatpak with custom installation
  services.flatpak.enable = true;
  xdg.portal.enable = true;
  xdg.portal.extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];

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
    serviceConfig = {
      ExecStart = "/sbin/agetty --autologin root --noclear %I $TERM";
    };
  };

  # Force headless mode (disable graphics)
  virtualisation.graphics = false;

  # QEMU networking: forward host port 2222 to VM port 22
  virtualisation.qemu.networkingOptions = [
    "-nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22"
  ];
}