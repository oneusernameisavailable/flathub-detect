{
  description = "NixOS VM for testing flathub-detect with custom installation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { config = { allowUnfree = true; }; };
    in
    {
      # NixOS VM configuration
      nixosConfigurations.flathub-test-vm = {
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
    };
}