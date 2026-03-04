{ pkgs, user, ... }:
{
  # ── Primary user (required for user-level system.defaults and homebrew) ──
  system.primaryUser = user;

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

  # ── Firewall (new API replacing system.defaults.alf) ──
  networking.applicationFirewall = {
    enable = true;
    enableStealthMode = true;
    allowSigned = true;
    allowSignedApp = false; # block unsigned downloaded apps
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

    taps = [
      "nikitabobko/tap"
    ];

    casks = [
      "aerospace"
      "firefox"
      "bitwarden"
      "discord"
      "spotify"
      "obsidian"
      "visual-studio-code"
      "slack"
      "telegram"
      "raycast"
    ];

  };

  # ── System packages (Darwin-specific CLI tools) ──
  environment.systemPackages = with pkgs; [
    pam-reattach # Touch ID in tmux
  ];

  # ── Enable zsh system-wide (macOS default shell) ──
  programs.zsh.enable = true;
}
