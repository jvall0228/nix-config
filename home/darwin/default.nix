{ ... }:
{
  imports = [
    ./aerospace.nix
  ];

  # ── Zsh configuration (macOS default shell) ──
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
  };
}
