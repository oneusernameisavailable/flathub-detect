{
  description = "NixOS VM for testing flathub-detect with custom installation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { config = { allowUnfree = true; }; system = "x86_64-linux"; };
    in
    {
      packages.x86_64-linux.flathub-test-vm = (nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (import (nixpkgs + "/nixos/modules/virtualisation/qemu-vm.nix"))
          ./nixos-test-vm.nix
        ];
      }).config.system.build.vm;
    };
}