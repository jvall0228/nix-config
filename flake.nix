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

  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, disko, ... }@inputs:
    let
      user = "javels";
      flakeUri = "github:jvall0228/nix-config";
      unstableFor = system: nixpkgs-unstable.legacyPackages.${system};
    in
    {
      # ── NixOS hosts ──────────────────────────────────────────
      nixosConfigurations.thinkpad = let system = "x86_64-linux"; in nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs user flakeUri; unstable = unstableFor system; };
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
              extraSpecialArgs = { inherit inputs user; unstable = unstableFor system; };
              backupFileExtension = "backup";
            };
          }
        ];
      };

      # ── Checks ─────────────────────────────────────────────
      checks.x86_64-linux.thinkpad =
        self.nixosConfigurations.thinkpad.config.system.build.toplevel;

      # TODO: Add nixosConfigurations.proxmox-vm (skip nvidia/hyprland/power)
      # TODO: Add homeConfigurations for standalone home-manager (Arch)
    };
}
