{ pkgs, ... }:
{
  home.packages = [ pkgs.fastfetch ];

  xdg.configFile."fastfetch/config.jsonc".text = builtins.toJSON {
    logo = {
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
