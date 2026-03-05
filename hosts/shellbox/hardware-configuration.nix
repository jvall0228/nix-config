{ ... }:
# Minimal — the DO config module (imported via do-networking.nix) provides
# qemu-guest.nix and virtio modules. This file exists per host convention.
{
  # Extra modules not in qemu-guest profile
  boot.initrd.availableKernelModules = [ "ahci" "sd_mod" ];
}
