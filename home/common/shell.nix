{ ... }:
{
  programs.bash = {
    enable = true;
    shellAliases = {
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
    };
  };

  programs.starship.enable = true;
}
