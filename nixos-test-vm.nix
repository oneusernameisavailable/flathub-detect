{ config, lib, pkgs, options, ... }:
{
  # Declare virtualisation options (normally provided by qemu-vm module)
  options.virtualisation = {
    memorySize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1024;
      description = "Memory size in megabytes";
    };
    cores = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Number of CPU cores";
    };
    diskSize = lib.mkOption {
      type = lib.types.either (lib.types.enum [ "auto" ]) lib.types.ints.positive;
      default = 1024;
      description = "Disk size in megabytes";
    };
    vmVariant = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "VM variant configuration";
    };
    qemu = {
      options = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "QEMU options";
      };
    };
  };

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

  # VM image settings
  virtualisation.vmVariant = "qemu";
  virtualisation.memorySize = 1024;
  virtualisation.cores = 2;
  virtualisation.diskSize = 8192;
  virtualisation.qemu.options = [
    "-m 1024"
    "-smp 2"
    "-nographic"
    "-serial stdio"
  ];
}