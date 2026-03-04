{ user, ... }:
{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = user;
        email = "jvall0228@users.noreply.github.com";
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };
}
