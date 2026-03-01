{ pkgs, user, config, flakeUri, ... }:
{
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
    efi.canTouchEfiVariables = true;
  };

  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 1048576;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "kernel.kptr_restrict" = 2;
    "kernel.yama.ptrace_scope" = 1;
    "kernel.dmesg_restrict" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
  };

  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = false;
  services.blueman.enable = true;

  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" ];
    shell = pkgs.bash;
  };

  environment.systemPackages = with pkgs; [
    vim git curl wget htop unzip file
  ];

  system.autoUpgrade = {
    enable = true;
    flake = "${flakeUri}#${config.networking.hostName}";
    dates = "04:00";
    allowReboot = false;
  };

  system.stateVersion = "25.05";
}
