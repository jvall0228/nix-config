{ pkgs, inputs, config, ... }:
let
  colors = config.lib.stylix.colors;
  colorsCss = pkgs.writeText "colors.css" ''
    :root {
      --base00: #${colors.base00};
      --base01: #${colors.base01};
      --base02: #${colors.base02};
      --base03: #${colors.base03};
      --base04: #${colors.base04};
      --base05: #${colors.base05};
      --base06: #${colors.base06};
      --base07: #${colors.base07};
      --base08: #${colors.base08};
      --base09: #${colors.base09};
      --base0A: #${colors.base0A};
      --base0B: #${colors.base0B};
      --base0C: #${colors.base0C};
      --base0D: #${colors.base0D};
      --base0E: #${colors.base0E};
      --base0F: #${colors.base0F};
      --font-mono: "JetBrainsMono Nerd Font";
      --font-sans: "Noto Sans";
      --border-radius: 8px;
    }
  '';
in {
  imports = [ inputs.ags.homeManagerModules.default ];

  programs.ags = {
    enable = true;
    extraPackages = with inputs.astal.packages.${pkgs.system}; [
      battery
      network
      bluetooth
      mpris
      wireplumber
      hyprland
      tray
      notifd
      powerprofiles
    ];
  };

  # Symlink AGS source files individually so we can also inject colors.css
  xdg.configFile = {
    "ags/app.ts".source = ./ags/app.ts;
    "ags/style.css".source = ./ags/style.css;
    "ags/lib/popups.ts".source = ./ags/lib/popups.ts;
    "ags/lib/utils.ts".source = ./ags/lib/utils.ts;
    "ags/widgets/Calendar.tsx".source = ./ags/widgets/Calendar.tsx;
    "ags/widgets/AudioMixer.tsx".source = ./ags/widgets/AudioMixer.tsx;
    "ags/widgets/Network.tsx".source = ./ags/widgets/Network.tsx;
    "ags/widgets/Bluetooth.tsx".source = ./ags/widgets/Bluetooth.tsx;
    "ags/widgets/Media.tsx".source = ./ags/widgets/Media.tsx;
    "ags/widgets/Dashboard.tsx".source = ./ags/widgets/Dashboard.tsx;
    "ags/widgets/Notifications.tsx".source = ./ags/widgets/Notifications.tsx;
    "ags/widgets/OSD.tsx".source = ./ags/widgets/OSD.tsx;
    "ags/colors.css".source = colorsCss;
  };
}
