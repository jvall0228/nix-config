{ pkgs, user, unstable, lib, ... }:
{
  imports = [
    ./common/shell.nix
    ./common/git.nix
    ./common/neovim.nix
    ./common/dev-tools.nix
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    ./linux
  ];

  home = {
    username = user;
    homeDirectory = "/home/${user}";
    stateVersion = "25.05";
  };

  home.packages = [
    unstable.claude-code
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
