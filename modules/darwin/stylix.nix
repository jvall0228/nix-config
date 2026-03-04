{ pkgs, ... }:
{
  stylix = {
    enable = true;
    autoEnable = false; # explicit opt-in — many NixOS targets don't exist on Darwin
    image = ../../assets/wallpaper.png;
    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyo-night-dark.yaml";

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      sansSerif = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
      serif = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
      };
    };

    # All targets (kitty, bat, btop) are home-manager level, not system level
    # They'll be auto-themed via stylix.homeManagerIntegration when autoEnable = true
  };
}
