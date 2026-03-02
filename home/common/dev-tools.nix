{ pkgs, unstable, ... }:
{
  home.packages = with pkgs; [
    ripgrep
    fd
    jq
    bat
    eza
    fzf
    gh
    lazygit
    python3
    nodejs
    rustup
    tmux
    unstable.claude-code
  ];
}
