{ ... }:
let
  btrfsMountOpts = [ "compress=zstd" "noatime" ];
in
{
  disko.devices = {
    disk.main = {
      device = "/dev/nvme0n1";  # verify with lsblk
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          esp = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              # allowDiscards: trades minor info leak (block usage patterns visible
              # to physical attacker) for SSD health via TRIM. Acceptable for laptop.
              settings.allowDiscards = true;
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@" = { mountpoint = "/"; mountOptions = btrfsMountOpts; };
                  "@home" = { mountpoint = "/home"; mountOptions = btrfsMountOpts; };
                  "@nix" = { mountpoint = "/nix"; mountOptions = btrfsMountOpts; };
                  "@swap" = { mountpoint = "/swap"; mountOptions = [ "noatime" ]; };
                };
              };
            };
          };
        };
      };
    };
  };
}
