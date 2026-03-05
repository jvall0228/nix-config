{ lib, user, ... }:
let
  sshKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHznnU/MK5vP++fgL197Ghc9RVB9PI8o+qoGnCVUNAgy";
in
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "shellbox";

  # GRUB bootloader (BIOS + EFI hybrid for DO)
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Serial console for DO web console access
  boot.kernelParams = lib.mkForce [
    "console=ttyS0"
    "slab_nomerge" "init_on_alloc=1" "init_on_free=1" "page_alloc.shuffle=1"
  ];

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
  users.users.${user}.openssh.authorizedKeys.keys = [ sshKey ];
  users.users.root.openssh.authorizedKeys.keys = [ sshKey ];

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

  # Firewall: SSH only (override Syncthing ports from core.nix)
  networking.firewall.allowedTCPPorts = lib.mkForce [ 22 ];
  networking.firewall.allowedUDPPorts = lib.mkForce [ ];

  # Override wifi MAC randomization (no wifi on a VPS)
  networking.networkmanager.wifi.macAddress = lib.mkForce "preserve";

  system.stateVersion = "25.05";
}
