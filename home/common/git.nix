{ user, ... }:
{
  programs.git = {
    enable = true;
    userName = user;
    # userEmail = "your@email.com";  # set this
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };
}
