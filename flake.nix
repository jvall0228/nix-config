{
  description = "javels — multi-platform nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, disko, nix-darwin, ... }@inputs:
    let
      user = "javels";
      unstableFor = system: nixpkgs-unstable.legacyPackages.${system};

      mkApp = system: name: {
        type = "app";
        program = "${(nixpkgs.legacyPackages.${system}.writeScriptBin name ''
          #!/usr/bin/env bash
          exec ${self}/apps/${name} "$@"
        '')}/bin/${name}";
      };
    in
    {
      # ── Convenience apps ─────────────────────────────────────
      apps.x86_64-linux = {
        build-switch = mkApp "x86_64-linux" "build-switch";
        clean = mkApp "x86_64-linux" "clean";
      };

      # ── NixOS hosts ──────────────────────────────────────────
      nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs user; unstable = unstableFor "x86_64-linux"; };
        modules = [
          disko.nixosModules.disko
          ./hosts/thinkpad/default.nix
          ./hosts/thinkpad/disko.nix
          ./modules/shared/nix.nix
          ./modules/nixos/core.nix
          ./modules/nixos/audio.nix
          ./modules/nixos/nvidia.nix
          ./modules/nixos/hyprland.nix
          ./modules/nixos/power.nix

          nixos-hardware.nixosModules.common-cpu-amd
          nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
          nixos-hardware.nixosModules.common-pc-laptop
          nixos-hardware.nixosModules.common-pc-laptop-ssd

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${user} = import ./home/default.nix;
              extraSpecialArgs = { inherit inputs user; unstable = unstableFor "x86_64-linux"; };
              backupFileExtension = "backup";
            };
          }
        ];
      };

      # TODO: Add nixosConfigurations.proxmox-vm (skip nvidia/hyprland/power)
      # TODO: Add darwinConfigurations.macbook (nix-darwin + home-manager.darwinModules)
      # TODO: Add homeConfigurations for standalone home-manager (Arch)
      # TODO: Add apps.aarch64-darwin with build-switch-darwin
    };
}
