{ pkgs, inputs, config, ... }:
let
  colors = config.lib.stylix.colors;
  # Pre-blurred wallpaper for the agent-mode lock curtain (AgentLock.tsx), matched
  # to hyprlock's background (blur_size 6 / passes 3, brightness 0.7) so the curtain
  # reads identical. Generated once at build time and injected into the AGS config
  # dir; the CSS references it as a relative url (see style.css .agentlock-bg).
  wallpaperBlur = pkgs.runCommand "agentlock-wallpaper-blur.png" { } ''
    ${pkgs.imagemagick}/bin/convert ${../../assets/wallpaper.png} \
      -blur 0x20 -modulate 70 png:$out
  '';

  colorsCss = pkgs.writeText "colors.css" ''
    @define-color base00 #${colors.base00};
    @define-color base01 #${colors.base01};
    @define-color base02 #${colors.base02};
    @define-color base03 #${colors.base03};
    @define-color base04 #${colors.base04};
    @define-color base05 #${colors.base05};
    @define-color base06 #${colors.base06};
    @define-color base07 #${colors.base07};
    @define-color base08 #${colors.base08};
    @define-color base09 #${colors.base09};
    @define-color base0A #${colors.base0A};
    @define-color base0B #${colors.base0B};
    @define-color base0C #${colors.base0C};
    @define-color base0D #${colors.base0D};
    @define-color base0E #${colors.base0E};
    @define-color base0F #${colors.base0F};
  '';
in {
  imports = [ inputs.ags.homeManagerModules.default ];

  programs.ags = {
    enable = true;
    configDir = pkgs.symlinkJoin {
      name = "ags-config";
      paths = [ ./ags ];
      postBuild = ''
        rm -f $out/colors.css
        cp ${colorsCss} $out/colors.css
        cp ${wallpaperBlur} $out/agentlock-wallpaper-blur.png
      '';
    };
    extraPackages = with inputs.astal.packages.${pkgs.stdenv.hostPlatform.system}; [
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

  # Supervise AGS as a user service so its popups self-heal if it crashes. It was
  # previously an unsupervised Hyprland exec-once, so a single crash left the
  # bar's dashboard/calendar/network/etc. silently gone until the next login.
  # Software-rendered (LIBGL_ALWAYS_SOFTWARE): the GTK layer-shell popups never
  # paint when their GL context lands on the runtime-suspended NVIDIA dGPU on
  # this hybrid GPU; llvmpipe sidesteps it and is negligible for these popups.
  # Scoped to AGS, not the global Hyprland env, so other apps keep hw accel.
  systemd.user.services.ags = {
    Unit = {
      Description = "AGS desktop shell (bar popups: dashboard, calendar, network, …)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      Environment = [
        "LIBGL_ALWAYS_SOFTWARE=1"
        "GALLIUM_DRIVER=llvmpipe"
      ];
      ExecStart = "${config.home.profileDirectory}/bin/ags run -g 3";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
