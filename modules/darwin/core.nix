{ pkgs, user, ... }:
{
  # ── Nix garbage collection (Darwin-specific launchd interval) ──
  nix.gc = {
    automatic = true;
    interval = [{ Hour = 4; Minute = 0; }]; # daily at 04:00
    options = "--delete-older-than 14d"; # more aggressive than NixOS (store grows faster without optimise)
  };

  # ── Security ──
  security.pam.services.sudo_local.touchIdAuth = true;

  # ── System preferences ──
  system.defaults = {
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.2;
      mru-spaces = false;
      orientation = "bottom";
      show-recents = false;
      tilesize = 48;
      minimize-to-application = true;
    };

    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      FXPreferredViewStyle = "clmv";
      FXEnableExtensionChangeWarning = false;
      QuitMenuItem = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
    };

    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      AppleInterfaceStyle = "Dark";
      AppleShowScrollBars = "Always";
      ApplePressAndHoldEnabled = false; # disable press-and-hold, enable key repeat
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      "com.apple.keyboard.fnState" = true;
      "com.apple.mouse.tapBehavior" = 1;
      "com.apple.trackpad.enableSecondaryClick" = true;
    };

    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };

    screencapture = {
      location = "~/Pictures/Screenshots";
      type = "png";
      disable-shadow = true;
    };

    loginwindow.GuestEnabled = false;

    # ── Firewall ──
    alf = {
      globalstate = 1; # enable firewall
      stealthenabled = 1; # don't respond to pings
      allowsignedenabled = 1; # allow signed apps
      allowdownloadsignedenabled = 0; # block unsigned downloaded apps
    };

    # ── Screen lock ──
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0; # require password immediately
    };

    CustomUserPreferences = {
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
    };
  };

  # ── Disable startup sound ──
  system.startup.chime = false;

  # ── Homebrew (GUI apps via casks) ──
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "uninstall"; # remove unlisted casks, but don't zap data
    };

    taps = [];

    brews = [
      "mas" # Mac App Store CLI
    ];

    casks = [
      "firefox"
      "1password"
      "discord"
      "spotify"
      "obsidian"
      "visual-studio-code"
      "slack"
      "telegram"
      "raycast"
    ];

    masApps = {
      # "Tailscale" = 1475387142;
    };
  };

  # ── System packages (Darwin-specific CLI tools) ──
  environment.systemPackages = with pkgs; [
    pam-reattach # Touch ID in tmux
  ];

  # ── Enable zsh system-wide (macOS default shell) ──
  programs.zsh.enable = true;
}
