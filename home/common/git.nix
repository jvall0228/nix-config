{ user, ... }:
{
  programs.git = {
    enable = true;
    userName = user;
    userEmail = "jaesonvalles@gmail.com";
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };
}
