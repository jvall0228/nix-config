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
    # Shell aliases inherited from home.shellAliases in home/common/shell.nix
  };
}
