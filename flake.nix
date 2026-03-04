{
  description = "javels — multi-platform nix config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    walker = {
      url = "github:abenz1267/walker";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    astal = {
      url = "github:aylur/astal";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ags = {
      url = "github:aylur/ags";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.astal.follows = "astal";
    };

  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, disko, lanzaboote, stylix, walker, ags, astal, ... }@inputs:
    let
      user = "javels";
      unstableFor = system: import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      # ── NixOS hosts ──────────────────────────────────────────
      nixosConfigurations.thinkpad = let system = "x86_64-linux"; in nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs user; unstable = unstableFor system; };
        modules = [
          disko.nixosModules.disko
          lanzaboote.nixosModules.lanzaboote
          ./hosts/thinkpad/default.nix
          ./hosts/thinkpad/disko.nix
          ./modules/shared/nix.nix
          ./modules/nixos/core.nix
          ./modules/nixos/audio.nix
          ./modules/nixos/nvidia.nix
          ./modules/nixos/hyprland.nix
          ./modules/nixos/power.nix
          ./modules/nixos/stylix.nix
          ./modules/nixos/greetd.nix
          ./modules/nixos/agent-context.nix
          stylix.nixosModules.stylix

          nixos-hardware.nixosModules.common-cpu-amd
          nixos-hardware.nixosModules.common-pc-laptop
          nixos-hardware.nixosModules.common-pc-laptop-ssd

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${user} = import ./home/default.nix;
              extraSpecialArgs = { inherit inputs user system; unstable = unstableFor system; };
              backupFileExtension = "backup";
            };
          }
        ];
      };

      # ── Checks ─────────────────────────────────────────────
      checks.x86_64-linux.thinkpad =
        self.nixosConfigurations.thinkpad.config.system.build.toplevel;

      # TODO: Add nixosConfigurations.proxmox-vm (skip nvidia/hyprland/power)
      # TODO: Add darwinConfigurations.macbook (nix-darwin + home-manager.darwinModules)
      # TODO: Add homeConfigurations for standalone home-manager (Arch)
      # TODO: Add apps.aarch64-darwin with build-switch-darwin
    };
}
