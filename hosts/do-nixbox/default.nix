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
  # Port 22 stays open on the PUBLIC interface for now. Closing it (SSH over
  # Tailscale only — todo 005 AC#4) is deliberately staged to a follow-up commit,
  # AFTER `tailscale up` is confirmed working, so the 04:00 auto-upgrade can't
  # lock the droplet out. Tailscale traffic (incl. SSH) is already allowed via
  # trustedInterfaces below, so the eventual cutover is just dropping 22 here.
  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Tailscale (todo 005): VPN mesh to thinkpad / macbook-pro. This enables the
  # daemon + CLI only; join the tailnet once, manually, after deploy:
  #   sudo tailscale up
  # No auth-key secret management (no sops-nix in this repo yet). rpfilter is
  # already loose here — useRoutingFeatures = "client" forces
  # networking.firewall.checkReversePath = "loose" — so if routed (exit-node /
  # subnet) packets still drop, the next step is checkReversePath = false, not "loose".
  services.tailscale = {
    enable = true;
    openFirewall = true;            # UDP 41641 for direct (NAT-traversal) links
    useRoutingFeatures = "client";  # allow using a subnet route / exit node
  };

  # Docker (todo 005): rootful daemon for containerized agent tools / MCP servers.
  # ${user} is added to the docker group below. Pin docker_29 explicitly: the
  # default `docker` package is 28.5.2, which nixpkgs 25.11 marks INSECURE
  # (docker_28 unmaintained since Nov 2025 → recommends docker_29+). Permitting
  # the insecure package would be the wrong call on a public-facing droplet.
  virtualisation.docker.enable = true;
  virtualisation.docker.package = pkgs.docker_29;

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
    extraGroups = [ "wheel" "docker" ];
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
