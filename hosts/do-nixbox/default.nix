{ pkgs, user, config, lib, ... }:
let
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHznnU/MK5vP++fgL197Ghc9RVB9PI8o+qoGnCVUNAgy"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEaaVvW4CkusjcsY1X+vwKJ+vUFrhJ3OSTtTHJs9BbbK ShellFish@iPad-20012026"
  ];
in
{
  imports = [
    ./hardware-configuration.nix
    ./do-networking.nix
  ];
  networking.hostName = "do-nixbox";

  # GRUB EFI support (DO module sets grub.devices, we add EFI for our disko ESP)
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  # DO module sets boot.growPartition = true — disable since disko manages layout
  boot.growPartition = lib.mkForce false;

  # Don't rebuild from DO user-data — we manage config via flake
  virtualisation.digitalOcean.rebuildFromUserData = false;

  # Networking configured by do-networking.nix (cloud-init)
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # SSH server — key-only auth
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      LogLevel = "VERBOSE";
    };
  };

  # SSH authorized keys for both user and root (nixos-anywhere needs root)
  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = sshKeys;
  };
  users.users.root.openssh.authorizedKeys.keys = sshKeys;

  security.sudo.execWheelOnly = true;
  security.sudo.wheelNeedsPassword = false;

  # fail2ban with progressive bans
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "168h";
      factor = "4";
    };
  };

  # zram swap (no physical swap on DO)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    unzip
    file
  ];

  system.autoUpgrade = {
    enable = true;
    flake = "github:jvall0228/nix-config/main#${config.networking.hostName}";
    dates = "04:00";
    allowReboot = false;
  };

  system.stateVersion = "25.05";
}
