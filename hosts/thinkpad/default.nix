{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "thinkpad";

  # Swap file for hibernation (adjust size to match RAM)
  swapDevices = [{
    device = "/swap/swapfile";
    size = 16 * 1024;  # 16GB — adjust to match RAM
  }];
}
