{ lib, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "thinkpad";

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
    configurationLimit = 10;
  };

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
