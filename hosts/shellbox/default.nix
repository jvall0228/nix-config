{ pkgs, user, config, lib, ... }:
let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHznnU/MK5vP++fgL197Ghc9RVB9PI8o+qoGnCVUNAgy";
in
{
  imports = [
    ./hardware-configuration.nix
    ./do-networking.nix
  ];
  networking.hostName = "shellbox";

  # GRUB bootloader (BIOS + EFI hybrid for DO)
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Serial console for DO web console access
  boot.kernelParams = [ "console=ttyS0" ];

  # Networking configured by do-networking.nix (metadata API)
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
    openssh.authorizedKeys.keys = [ sshKey ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

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
