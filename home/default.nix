{ user, system, lib, ... }:
{
  imports = [
    ./common/shell.nix
    ./common/git.nix
    ./common/neovim.nix
    ./common/dev-tools.nix
    ./common/kitty.nix
    ./common/tmux.nix
    ./common/fastfetch.nix
  ] ++ lib.optionals (builtins.elem system [ "x86_64-linux" "aarch64-linux" ]) [
    ./linux
  ];

  home = {
    username = user;
    homeDirectory = "/home/${user}";
    stateVersion = "25.05";
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
