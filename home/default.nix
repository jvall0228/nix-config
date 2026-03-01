{ pkgs, user, unstable, lib, ... }:
{
  imports = [
    ./common/shell.nix
    ./common/git.nix
    ./common/neovim.nix
    ./common/dev-tools.nix
  ] ++ lib.optionals pkgs.stdenv.isLinux [
    ./linux
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    ./darwin
  ];

  home = {
    username = user;
    homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${user}" else "/home/${user}";
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
