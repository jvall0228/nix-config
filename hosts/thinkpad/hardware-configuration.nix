# This file will be generated during NixOS installation.
# Run: sudo nixos-generate-config --no-filesystems --root /mnt
# Then copy the generated file here.
{ ... }:
{
  imports = [ ];

  # Placeholder — replace with output of nixos-generate-config
  # Build will fail until this is replaced with real hardware config.
  system.extraDependencies = throw
    "Replace hosts/thinkpad/hardware-configuration.nix with the output of: sudo nixos-generate-config --no-filesystems --root /mnt";
}
