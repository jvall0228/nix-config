{ modulesPath, lib, ... }:
# DigitalOcean networking via cloud-init.
# DO does not provide a DHCP server — IP assignment is static.
# cloud-init fetches network config from the DO metadata API (169.254.169.254)
# and configures interfaces via systemd-networkd.
# Reference: https://github.com/numtide/srvos/blob/main/nixos/hardware/digitalocean/droplet.nix
{
  imports = [
    (modulesPath + "/virtualisation/digital-ocean-config.nix")
  ];

  # DHCP does not work on DO — cloud-init handles static IP assignment
  networking.useDHCP = lib.mkForce false;
  networking.useNetworkd = true;

  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [ "DigitalOcean" ];
      datasource.DigitalOcean = { };
    };
  };
}
