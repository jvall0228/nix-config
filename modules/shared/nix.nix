{ user, lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = !pkgs.stdenv.isDarwin; # corrupts store on Darwin
    max-jobs = "auto";
    cores = 0;
    trusted-users = [ "root" ] ++ lib.optionals pkgs.stdenv.isDarwin [ user ];
    allowed-users = [ "root" user ];
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://walker.cachix.org"
      "https://walker-git.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
      "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
    ];
  };

  # NixOS: systemd timer syntax
  # Darwin gc is configured in modules/darwin/core.nix (launchd interval format)
  nix.gc = lib.mkIf pkgs.stdenv.isLinux {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
