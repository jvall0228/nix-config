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
      url = "github:nix-community/stylix/release-25.11";
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

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, disko, lanzaboote, stylix, walker, ags, astal, nix-darwin, ... }@inputs:
    let
      user = "javels";
      unstableFor = system: import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      hmConfig = system: { headless ? false }: {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          users.${user} = import ./home/default.nix;
          extraSpecialArgs = { inherit inputs user system headless; unstable = unstableFor system; };
          backupFileExtension = "backup";
        };
      };
    in
    {
      # ── NixOS hosts ──────────────────────────────────────────
      nixosConfigurations.thinkpad = let system = "x86_64-linux"; in nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs user; unstable = unstableFor system; };
        modules = [
          { nixpkgs.hostPlatform = system; }
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
          (hmConfig system {})
        ];
      };

      nixosConfigurations.do-nixbox = let system = "x86_64-linux"; in nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs user; unstable = unstableFor system; };
        modules = [
          { nixpkgs.hostPlatform = system; }
          ./hosts/do-nixbox/default.nix
          ./modules/shared/nix.nix
          ./modules/nixos/agent-context.nix
          home-manager.nixosModules.home-manager
          (hmConfig system { headless = true; })
        ];
      };

      # ── Checks ─────────────────────────────────────────────
      checks.x86_64-linux.thinkpad =
        self.nixosConfigurations.thinkpad.config.system.build.toplevel;
      checks.x86_64-linux.do-nixbox =
        self.nixosConfigurations.do-nixbox.config.system.build.toplevel;

      # ── Darwin hosts ────────────────────────────────────────
      darwinConfigurations.macbook-pro = let system = "aarch64-darwin"; in nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs user; unstable = unstableFor system; };
        modules = [
          { nixpkgs.hostPlatform = system; }
          ./hosts/macbook-pro/default.nix
          ./modules/shared/nix.nix
          ./modules/darwin/core.nix
          stylix.darwinModules.stylix
          ./modules/darwin/stylix.nix

          home-manager.darwinModules.home-manager
          (hmConfig system {})
        ];
      };

      # ── Checks ─────────────────────────────────────────────
      checks.aarch64-darwin.macbook-pro =
        self.darwinConfigurations.macbook-pro.system;

      # ── Packages ───────────────────────────────────────────
      packages.x86_64-linux.do-nixbox-image =
        (self.nixosConfigurations.do-nixbox.extendModules {
          modules = [ ./hosts/do-nixbox/image.nix ];
        }).config.system.build.digitalOceanImage;

      # TODO: Add nixosConfigurations.proxmox-vm (skip nvidia/hyprland/power, use headless hmConfig)
      # TODO: Add homeConfigurations for standalone home-manager (Arch)
    };
}
