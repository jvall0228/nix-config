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
    claudemaxx = "claude --dangerously-skip-permissions --model 'opus[1m]' --effort high";
  };

  home.sessionVariables = {
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
  };

  programs.bash.enable = true;
  programs.starship.enable = true;
}
