{ lib, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "thinkpad";

  # First install: use systemd-boot. After first boot, create secure boot
  # keys with sbctl, then switch to lanzaboote (see post-install steps).
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;
  # boot.loader.systemd-boot.enable = lib.mkForce false;
  # boot.lanzaboote = {
  #   enable = true;
  #   pkiBundle = "/etc/secureboot";
  #   configurationLimit = 10;
  # };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = false;
  services.blueman.enable = true;

  # Swap file for hibernation (adjust size to match RAM)
  swapDevices = [{
    device = "/swap/swapfile";
    size = 16 * 1024;  # 16GB — adjust to match RAM
  }];

  system.stateVersion = "25.05";
}
