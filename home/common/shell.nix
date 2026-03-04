{ ... }:
{
  home.shellAliases = {
    ll = "eza -la";
    la = "eza -a";
    lt = "eza --tree";
    cat = "bat";
    g = "git";
    gs = "git status";
    gd = "git diff";
    gc = "git commit";
    gp = "git push";
    gl = "git log --oneline --graph";
    claudex = "claude --dangerously-skip-permissions";
  };

  programs.bash.enable = true;
  programs.starship.enable = true;
}
