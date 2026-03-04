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

    # Explicit target opt-ins for Darwin
    targets = {
      kitty.enable = true;
      bat.enable = true;
      btop.enable = true;
    };
  };
}
