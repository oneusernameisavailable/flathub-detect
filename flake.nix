{
  description = "NixOS VM for testing flathub-detect with custom installation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs { inherit system; config = { allowUnfree = true; }; };
    in {
      # NixOS VM configuration
      nixosConfigurations.flathub-test = pkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./nixos-test-vm.nix ];
      };

      # VM builder
      nixosConfigurations.flathub-test-vm = pkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          { config, pkgs, ... }: {
            imports = [
              <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
              ./nixos-test-vm.nix
            ];
            
            # VM-specific settings
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
            
            # Build VM image
            system.build.vm = pkgs.runCommandLocal "nixos-vm" {
              buildInputs = [ pkgs.qemu ];
            } ''
              mkdir -p $out
              ${config.system.build.toplevel}/bin/run-nixos-vm -m 1024 -c 2 -snapshot -nographic > $out/run-vm.sh
              chmod +x $out/run-vm.sh
            '';
          }
        ];
      };
    in {
      # VM runner script
      defaultPackage.${system} = self.nixosConfigurations.flathub-test-vm.config.system.build.vm;
      
      # Also provide the configuration for reference
      nixosConfigurations = {
        flathub-test = self.nixosConfigurations.flathub-test;
        flathub-test-vm = self.nixosConfigurations.flathub-test-vm;
      };
    }
  );
}