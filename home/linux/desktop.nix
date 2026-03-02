{ pkgs, ... }:
{
  imports = [ ./hyprland.nix ];

  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    firefox vscode
    nerd-fonts.symbols-only
    font-awesome
  ];
}
