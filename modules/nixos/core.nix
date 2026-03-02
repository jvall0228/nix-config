{ pkgs, user, config, ... }:
{
  boot.initrd.systemd.enable = true;

  boot.kernelParams = [
    "quiet" "loglevel=3" "systemd.show_status=auto"
    "slab_nomerge" "init_on_alloc=1" "init_on_free=1" "page_alloc.shuffle=1"
  ];

  boot.blacklistedKernelModules = [ "dccp" "sctp" "rds" "tipc" ];

  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 1048576;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 1;
    "kernel.dmesg_restrict" = 1;
    "kernel.sysrq" = 0;
    "fs.protected_symlinks" = 1;
    "fs.protected_hardlinks" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.default.accept_ra" = 0;
  };

  networking.networkmanager = {
    enable = true;
    wifi.macAddress = "random";
  };
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22000 ];
  networking.firewall.allowedUDPPorts = [ 22000 21027 ];
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  security.sudo.execWheelOnly = true;
  # Passwordless sudo: acceptable for single-user LUKS-encrypted workstations.
  # Override with `security.sudo.wheelNeedsPassword = lib.mkForce true;` for server hosts.
  security.sudo.wheelNeedsPassword = false;

  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" ];
    shell = pkgs.bash;
  };

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    unzip
    file
    sbctl
  ];

  system.autoUpgrade = {
    enable = true;
    flake = "github:jvall0228/nix-config/main#${config.networking.hostName}";
    dates = "04:00";
    allowReboot = false;
  };
}
