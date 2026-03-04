{ user, pkgs, ... }:
{
  networking.hostName = "macbook-pro";
  networking.localHostName = "macbook-pro";
  networking.computerName = "macbook-pro";

  users.users.${user} = {
    home = "/Users/${user}";
    shell = pkgs.zsh;
    description = user;
  };
  users.knownUsers = [ user ];

  system.stateVersion = 6; # nix-darwin: integer, not string. Never change.
}
