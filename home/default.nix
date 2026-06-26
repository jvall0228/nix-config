{ user, system, headless ? false, lib, ... }:
let
  isLinux = builtins.elem system [ "x86_64-linux" "aarch64-linux" ];
  isDarwin = builtins.elem system [ "x86_64-darwin" "aarch64-darwin" ];
in
{
  imports = [
    ./common/shell.nix
    ./common/git.nix
    ./common/neovim.nix
    ./common/dev-tools.nix
    ./common/tmux.nix
    ./common/fastfetch.nix
  ] ++ lib.optionals (!headless) [
    # kitty is a GUI terminal (~150 MB closure) — useless on headless hosts.
    ./common/kitty.nix
  ] ++ lib.optionals (isLinux && !headless) [
    ./linux
  ] ++ lib.optionals isDarwin [
    ./darwin
  ];

  home = {
    username = user;
    homeDirectory = if isLinux then "/home/${user}" else "/Users/${user}";
    stateVersion = "25.05";
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
