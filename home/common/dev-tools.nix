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
    unstable.claude-code
    unstable.codex
    unstable.gemini-cli
    unstable.opencode
  ];
}
