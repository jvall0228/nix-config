{ modulesPath, ... }:
# Adds the digitalOceanImage build target for producing a QCOW2 image.
# Only included when building the image (via extendModules in flake.nix),
# not in the running system config.
{
  imports = [ (modulesPath + "/virtualisation/digital-ocean-image.nix") ];
}
