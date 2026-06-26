{ pkgs, headless ? false, ... }:
{
  home.packages = [ pkgs.fastfetch ];

  xdg.configFile."fastfetch/config.jsonc".text = builtins.toJSON {
    # kitty-direct renders an inline image via the kitty graphics protocol,
    # which is unavailable over SSH — fall back to the built-in distro logo
    # on headless hosts.
    logo =
      if headless then {
        type = "builtin";
      } else {
        type = "kitty-direct";
        source = ../../assets/avatar.png;
        width = 18;
        padding = { top = 1; };
      };
    modules = [
      "title"
      "separator"
      "os"
      "host"
      "kernel"
      "uptime"
      "packages"
      "shell"
      "display"
      "de"
      "wm"
      "terminal"
      "cpu"
      "gpu"
      "memory"
      "disk"
      "battery"
      "separator"
      "colors"
    ];
  };
}
