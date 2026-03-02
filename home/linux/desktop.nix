{ pkgs, ... }:
{
  imports = [ ./hyprland.nix ];

  fonts.fontconfig.enable = true;

  home.packages = with pkgs; [
    # Browsers & editors
    firefox
    vscode

    # Communication
    discord
    slack
    telegram-desktop
    obsidian

    # Media
    mpv

    # File manager
    nautilus

    # Fonts
    nerd-fonts.jetbrains-mono
    noto-fonts-color-emoji
    noto-fonts-cjk-sans
    font-awesome

    # Icons
    papirus-icon-theme
  ];

  # Syncthing file sync
  services.syncthing.enable = true;

  # User avatar (used by greetd/regreet, accountsservice)
  home.file.".face".source = ../../assets/avatar.png;
}
