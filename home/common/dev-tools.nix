{ pkgs, unstable, ... }:
{
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    bat
    eza
    fzf
    lazygit
    python3
    nodejs
    rustup
    unstable.claude-code
  ];
}
