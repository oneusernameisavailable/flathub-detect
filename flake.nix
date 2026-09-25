{
  description = "NixOS VM for testing flathub-detect with custom installation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      pkgsFor = system: import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };

      makeVM = system: pkgsFor system.lib.nixosSystem {
        system = system;
        modules = [
          {
            imports = [
              <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
              ./nixos-test-vm.nix
            ];

            virtualisation = {
              qemu = {
                enable = true;
                guestAgent.enable = true;
                options = [
                  "-m 1024"
                  "-smp 2"
                  "-nographic"
                  "-serial stdio"
                ];
              };
            };

            system.build.vm = { config, pkgs, ... }: let
              toplevel = config.system.build.toplevel;
            in pkgsFor system.runCommandLocal "nixos-vm" {
              buildInputs = [ pkgs.qemu ];
              toplevel = toplevel;
            } ''
              mkdir -p $out
              ${toplevel}/bin/run-nixos-vm -m 1024 -c 2 -snapshot -nographic > $out/run-vm.sh
              chmod +x $out/run-vm.sh
            '';
          }
        ];
      };

    in {
      nixosConfigurations.flathub-test-vm = pkgsFor."x86_64-linux".lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            imports = [
              <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
              ./nixos-test-vm.nix
            ];

            virtualisation = {
              qemu = {
                enable = true;
                guestAgent.enable = true;
                options = [
                  "-m 1024"
                  "-smp 2"
                  "-nographic"
                  "-serial stdio"
                ];
              };
            };

            system.build.vm = { config, pkgs, ... }: let
              toplevel = config.system.build.toplevel;
            in pkgsFor."x86_64-linux".runCommandLocal "nixos-vm" {
              buildInputs = [ pkgsFor."x86_64-linux".qemu ];
              toplevel = toplevel;
            } ''
              mkdir -p $out
              ${toplevel}/bin/run-nixos-vm -m 1024 -c 2 -snapshot -nographic > $out/run-vm.sh
              chmod +x $out/run-vm.sh
            '';
          }
        ];
      };

      packages.x86_64-linux.flathub-test-vm = (import nixpkgs {
        system = "x86_64-linux";
        config = { allowUnfree = true; };
      }).lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          {
            imports = [
              <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
              ./nixos-test-vm.nix
            ];

            virtualisation = {
              qemu = {
                enable = true;
                guestAgent.enable = true;
                options = [
                  "-m 1024"
                  "-smp 2"
                  "-nographic"
                  "-serial stdio"
                ];
              };
            };

            system.build.vm = { config, pkgs, ... }: let
              toplevel = config.system.build.toplevel;
            in pkgs.runCommandLocal "nixos-vm" {
              buildInputs = [ pkgs.qemu ];
              toplevel = toplevel;
            } ''
              mkdir -p $out
              ${toplevel}/bin/run-nixos-vm -m 1024 -c 2 -snapshot -nographic > $out/run-vm.sh
              chmod +x $out/run-vm.sh
            '';
          }
        ];
      };
    };
}