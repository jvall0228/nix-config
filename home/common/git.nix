{ user, ... }:
{
  programs.git = {
    enable = true;
    userName = user;
    userEmail = "jvall0228@users.noreply.github.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };
}
