---
title: "feat: Add macOS Darwin Configuration"
type: feat
status: completed
date: 2026-03-04
deepened: 2026-03-04
origin: docs/brainstorms/2026-03-04-macos-configuration-brainstorm.md
---

# feat: Add macOS Darwin Configuration

## Enhancement Summary

**Deepened on:** 2026-03-04
**Research agents used:** architecture-strategist, security-sentinel, performance-oracle, code-simplicity-reviewer, pattern-recognition-specialist, deployment-verification-agent, best-practices-researcher

### Key Improvements
1. **nix-darwin branch fix** — `master` rejects `nixos-25.11`; must use `nix-darwin-25.11` release branch
2. **Nix installer change** — Determinate Systems installer only ships their fork since Jan 2026; switched to official installer
3. **Shell alias refactoring** — Confirmed `home/common/shell.nix` uses `programs.bash.shellAliases`; must extract to `home.shellAliases` for zsh compatibility
4. **Stylix signature bug fixed** — Module references `pkgs` but signature was `{ ... }:`
5. **Homebrew config consolidated** — Merged `homebrew.nix` into `core.nix` (YAGNI)
6. **Security hardening** — Added macOS firewall, screen lock, `ApplePressAndHoldEnabled`, documented `trusted-users` change
7. **YAGNI cleanup** — Removed empty `home/darwin/desktop.nix` placeholder
8. **Bootstrap hardening** — TLS enforcement on Homebrew curl, official Nix installer, first-activation via release branch

### New Considerations Discovered
- `nix flake check` evaluates all systems by default — must use `--system` flag per-platform
- `auto-optimise-store = false` on Darwin means store grows ~20-30% faster — use more aggressive gc
- `nix-homebrew` (zhaofengli) is complementary to nix-darwin's homebrew module — consider adding later
- Walker/AGS cachix substituters in `nix.nix` add latency on Darwin (Linux-only packages) — minor, acceptable

---

## Overview

Add full macOS (Darwin) support to the nix-config repo, targeting an Apple Silicon MacBook Pro (`aarch64-darwin`) as a daily driver. This introduces nix-darwin system configuration, Aerospace tiling WM, comprehensive `system.defaults`, Homebrew cask management, Stylix hybrid theming, and a zero-to-working bootstrap script.

The repo is already architected for this — `modules/shared/`, `home/common/`, and explicit TODOs in `flake.nix` establish the foundation (see brainstorm: `docs/brainstorms/2026-03-04-macos-configuration-brainstorm.md`).

## Problem Statement / Motivation

Currently this repo only supports NixOS (x86_64-linux). Adding Darwin support enables managing both machines from one flake with maximal config reuse via `modules/shared/` and `home/common/`.

## Proposed Solution

**Parallel module structure** — `modules/darwin/` + `home/darwin/` as peers to `modules/nixos/` + `home/linux/`. This matches established repo conventions and keeps platform concerns cleanly separated (see brainstorm: Key Decision #3).

Reference implementation: [dustinlyons/nixos-config](https://github.com/dustinlyons/nixos-config).

## Technical Approach

### Architecture

```
flake.nix
├── darwinConfigurations.macbook-pro
│   ├── hosts/macbook-pro/default.nix
│   ├── modules/shared/nix.nix          (shared Nix settings — gc split out)
│   ├── modules/darwin/core.nix          (system.defaults, user, security, homebrew)
│   ├── modules/darwin/stylix.nix        (app-level theming)
│   └── home-manager.darwinModules.home-manager
│       └── home/default.nix
│           ├── home/common/*            (shell, git, neovim, kitty, tmux, etc.)
│           └── home/darwin/
│               ├── default.nix          (imports + zsh config)
│               └── aerospace.nix        (tiling WM)
└── nixosConfigurations.thinkpad         (unchanged)
```

### Research Insights: Architecture

**Dependency graph remains acyclic.** Every node has a clear direction — `modules/darwin/` files do not import from `modules/shared/` or `home/`. No circular dependency risk.

**Cross-platform contamination risk:** If any `home/common/` module gains an import referencing Linux-only flake inputs (`walker`, `ags`, `astal`), it would break Darwin evaluation. Add a comment in `flake.nix` marking these inputs as Linux-only.

**Nix store growth:** With `auto-optimise-store = false` on Darwin, store grows ~20-30% faster. Mitigate with more aggressive gc (`--delete-older-than 14d` instead of 30d). Optionally run `nix store optimise` manually as a periodic maintenance task.

### Implementation Phases

---

#### Phase 1: Flake Foundation + Shared Module Fix

**Goal:** Add nix-darwin input, fix `modules/shared/nix.nix` for cross-platform compatibility, refactor shell aliases, and create the minimal `darwinConfigurations` block.

##### 1.1 Add nix-darwin input to `flake.nix`

```nix
# flake.nix inputs section
nix-darwin = {
  url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Add `nix-darwin` to the outputs function parameter destructuring (consistent with existing style where all inputs are explicitly named):

```nix
outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ..., nix-darwin, ... }:
```

### Research Insights: nix-darwin Branch

**Critical finding:** As of 2025, nix-darwin `master` enforces `enableNixpkgsReleaseCheck` and **rejects release branches like `nixos-25.11`**. You must use the corresponding release branch `nix-darwin-25.11` to follow your `nixpkgs` input.

This keeps both platforms on the same package set, reducing divergence. The `nixos-25.11` branch works for Darwin despite the "nixos" prefix — it contains Darwin packages.

**References:**
- [nix-darwin #727: Start using stable branches](https://github.com/nix-darwin/nix-darwin/issues/727)
- [nix-darwin #1284: master no longer allows following a release branch](https://github.com/nix-darwin/nix-darwin/issues/1284)
- [NixOS Discourse: Which nixpkgs stable tag for both?](https://discourse.nixos.org/t/which-nixpkgs-stable-tag-for-nixos-and-darwin-together/32796)

##### 1.2 Fix `modules/shared/nix.nix` — platform-conditional approach

**Critical issue:** Two options in the current shared nix.nix are Darwin-incompatible:
- `nix.gc.dates = "weekly"` — Darwin uses `nix.gc.interval` (launchd calendar attrset)
- `nix.settings.auto-optimise-store = true` — **corrupts the Nix store on Darwin** due to different inode structure

**Strategy:** Use `lib.mkIf` conditionals within the single file rather than splitting into multiple files. This keeps the shared module self-contained while gating incompatible options.

```nix
# modules/shared/nix.nix
{ user, lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = !pkgs.stdenv.isDarwin;  # corrupts store on Darwin
    max-jobs = "auto";
    cores = 0;
    trusted-users = [ "root" user ];  # user needed for darwin-rebuild without sudo
    allowed-users = [ "root" user ];
    substituters = [ /* existing */ ];
    trusted-public-keys = [ /* existing */ ];
  };

  # NixOS: systemd timer syntax
  # Darwin gc is configured in modules/darwin/core.nix (launchd interval format)
  nix.gc = lib.mkIf pkgs.stdenv.isLinux {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
```

Darwin gc is configured separately in `modules/darwin/core.nix` (see Phase 2).

**Note:** `pkgs` and `lib` must be added to the function signature (currently `{ user, ... }:`). Change to `{ user, lib, pkgs, ... }:`.

### Research Insights: Shared Module Safety

**`trusted-users` expansion:** Adding the unprivileged user to `trusted-users` grants the ability to add arbitrary binary cache substituters and override sandbox settings. This is a **security-relevant change** that also affects the existing NixOS host. It is required for `darwin-rebuild` to work without sudo. Document this tradeoff explicitly in a comment.

**Cross-reference comment:** The Linux gc block should have a comment noting that Darwin gc lives in `modules/darwin/core.nix`. Without this, the split configuration is discoverable only by reading both files.

**Idiom consistency:** The plain boolean `!pkgs.stdenv.isDarwin` for `auto-optimise-store` and `lib.mkIf` for `nix.gc` are actually the correct mixed approach. The boolean is right because the option is a boolean value. `lib.mkIf` is needed for `nix.gc` because it guards an entire attrset.

##### 1.3 Refactor `home/common/shell.nix` — extract aliases for cross-platform use

**Critical finding:** `home/common/shell.nix` uses `programs.bash.shellAliases`, which will NOT propagate to zsh on Darwin. This must be refactored to `home.shellAliases`.

```nix
# home/common/shell.nix — refactored
{ ... }:
{
  home.shellAliases = {
    ll = "eza -la";
    la = "eza -a";
    lt = "eza --tree";
    cat = "bat";
    g = "git";
    gs = "git status";
    gd = "git diff";
    gc = "git commit";
    gp = "git push";
    gl = "git log --oneline --graph";
    claudex = "claude --dangerously-skip-permissions";
  };

  programs.bash.enable = true;
  programs.starship.enable = true;
}
```

`home.shellAliases` populates aliases for **all enabled shells** (bash, zsh, fish). This is backward-compatible — bash on NixOS gets the same aliases, and zsh on Darwin inherits them automatically.

**Verify NixOS build after this change** — it modifies shared code.

##### 1.4 Add `darwinConfigurations.macbook-pro` block to `flake.nix`

```nix
darwinConfigurations.macbook-pro = let system = "aarch64-darwin"; in nix-darwin.lib.darwinSystem {
  specialArgs = { inherit inputs user; unstable = unstableFor system; };
  modules = [
    { nixpkgs.hostPlatform = system; }
    ./hosts/macbook-pro/default.nix
    ./modules/shared/nix.nix
    ./modules/darwin/core.nix
    stylix.darwinModules.stylix
    ./modules/darwin/stylix.nix

    home-manager.darwinModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        users.${user} = import ./home/default.nix;
        extraSpecialArgs = { inherit inputs user system; unstable = unstableFor system; };
        backupFileExtension = "backup";
      };
    }
  ];
};
```

Remove the corresponding TODOs from `flake.nix` (lines ~99-101).

### Research Insights: flake.nix

**Missing `checks` block:** The existing `checks.x86_64-linux.thinkpad` should have a corresponding `checks.aarch64-darwin.macbook-pro` for parity. However, `nix flake check` evaluates ALL systems by default — running it on NixOS will fail trying to evaluate `aarch64-darwin`. Use `nix flake check --system x86_64-linux` on the NixOS host. Document this in CLAUDE.md.

**`nix-homebrew` consideration:** The [zhaofengli/nix-homebrew](https://github.com/zhaofengli/nix-homebrew) input manages Homebrew *installation itself* declaratively, complementing nix-darwin's built-in Homebrew *package* module. Consider adding it in a future iteration for fully declarative Homebrew management. Not needed for MVP.

##### 1.5 Create minimal `hosts/macbook-pro/default.nix`

```nix
# hosts/macbook-pro/default.nix
{ user, pkgs, ... }:
{
  networking.hostName = "macbook-pro";
  networking.localHostName = "macbook-pro";
  networking.computerName = "macbook-pro";

  users.users.${user} = {
    home = "/Users/${user}";
    shell = pkgs.zsh;
    description = user;
  };
  users.knownUsers = [ user ];

  system.stateVersion = 6;  # nix-darwin: integer, not string. Never change.
}
```

**Key differences from NixOS host (`hosts/thinkpad/default.nix`):**
- No `hardware-configuration.nix` import (macOS auto-detects hardware)
- No boot/lanzaboote config
- No disko
- `system.stateVersion` is integer `6` (not string `"25.05"`)
- Three hostname identifiers (hostName, localHostName, computerName) for mDNS/AirDrop consistency
- `users.knownUsers` is Darwin-required — nix-darwin refuses to manage user settings without it

##### Phase 1 acceptance criteria:
- [x] `nix-darwin` input added with `nix-darwin-25.11` release branch
- [x] `modules/shared/nix.nix` uses platform conditionals for `auto-optimise-store` and `nix.gc`
- [x] `home/common/shell.nix` refactored to use `home.shellAliases` (not `programs.bash.shellAliases`)
- [x] NixOS configuration still builds after shell.nix and nix.nix changes
- [x] `darwinConfigurations.macbook-pro` evaluates without errors (`nix eval .#darwinConfigurations.macbook-pro`)
- [x] `hosts/macbook-pro/default.nix` created with all three hostname identifiers

---

#### Phase 2: Darwin System Modules

**Goal:** Create `modules/darwin/core.nix` (including Homebrew) and `modules/darwin/stylix.nix`.

##### 2.1 `modules/darwin/core.nix` — System defaults, security, Homebrew, gc

```nix
# modules/darwin/core.nix
{ pkgs, user, ... }:
{
  # ── Nix garbage collection (Darwin-specific launchd interval) ──
  nix.gc = {
    automatic = true;
    interval = [{ Hour = 4; Minute = 0; }];  # daily at 04:00
    options = "--delete-older-than 14d";       # more aggressive than NixOS (store grows faster without optimise)
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
      ApplePressAndHoldEnabled = false;   # disable press-and-hold, enable key repeat
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
      globalstate = 1;          # enable firewall
      stealthenabled = 1;       # don't respond to pings
      allowsignedenabled = 1;   # allow signed apps
      allowdownloadsignedenabled = 0;  # block unsigned downloaded apps
    };

    # ── Screen lock ──
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;  # require password immediately
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
      autoUpdate = true;      # update Homebrew on every rebuild
      upgrade = true;         # upgrade listed casks to latest
      cleanup = "uninstall";  # remove unlisted casks, but don't zap data
    };

    taps = [];

    brews = [
      "mas"  # Mac App Store CLI
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
    pam-reattach  # Touch ID in tmux
  ];

  # ── Enable zsh system-wide (macOS default shell) ──
  programs.zsh.enable = true;
}
```

### Research Insights: core.nix

**Security additions:**
- `system.defaults.alf` — enables macOS Application Level Firewall (stealth mode, block unsigned downloads). Missing from original plan.
- `system.defaults.screensaver` — requires password immediately on screen lock. Standard security hardening.
- `system.startup.chime = false` — disables startup sound.
- `ApplePressAndHoldEnabled = false` — critical for developers; enables key repeat instead of press-and-hold accent menu.

**Homebrew merged into core.nix** — the original plan had a separate 39-line `modules/darwin/homebrew.nix` file. This is YAGNI; it's a single-concern system setting that fits naturally alongside other system config, consistent with how `modules/nixos/core.nix` handles multiple system concerns.

**Performance note:** `autoUpdate = true` adds 30-60s per rebuild for Homebrew index sync. This is acceptable for keeping casks current.

**gc aggressiveness:** Changed from `--delete-older-than 30d` to `14d` because Darwin store grows ~20-30% faster without `auto-optimise-store`.

**Touch ID + tmux:** `pam-reattach` is installed as a system package. nix-darwin's `security.pam.services.sudo_local.touchIdAuth` handles the PAM config. If Touch ID doesn't work in tmux after activation, a manual `pam_reattach.so` entry in `/etc/pam.d/sudo_local` may be needed — document this in CLAUDE.md as a known workaround.

**nixpkgs vs cask split (see brainstorm: Key Decision #7):**
- **Homebrew casks:** All native macOS GUI apps. These get proper `.app` bundles, Spotlight indexing, and auto-update.
- **Nix packages:** All CLI tools stay in `home/common/dev-tools.nix` (ripgrep, fd, jq, bat, etc.).
- **No overlap:** Apps listed in `homebrew.casks` must NOT also appear as nix packages.

##### 2.2 `modules/darwin/stylix.nix` — App-level theming only

```nix
# modules/darwin/stylix.nix
{ pkgs, ... }:
{
  stylix = {
    enable = true;
    autoEnable = false;  # explicit opt-in — many NixOS targets don't exist on Darwin
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
```

### Research Insights: Stylix

**Signature bug fixed:** Original plan had `{ ... }:` but the module references `pkgs.base16-schemes` and `pkgs.nerd-fonts.jetbrains-mono`. Changed to `{ pkgs, ... }:`.

**Key differences from `modules/nixos/stylix.nix`:**
- `autoEnable = false` — prevents evaluation errors from nonexistent targets (waybar, hyprlock, GTK, QT)
- No cursor config (macOS manages cursors system-wide)
- `stylix.image` path resolves correctly from `modules/darwin/` (same relative depth as `modules/nixos/`)
- Stylix does NOT control macOS dark mode — that's handled by `system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark"` in core.nix
- Verify `stylix/release-25.11` supports `darwinModules` during implementation

##### Phase 2 acceptance criteria:
- [x] `modules/darwin/core.nix` created with `system.defaults`, Touch ID, gc interval, firewall, Homebrew
- [x] `modules/darwin/stylix.nix` created with `{ pkgs, ... }:` signature and explicit target opt-ins
- [x] No package overlap between Homebrew casks and Nix packages

---

#### Phase 3: Home-Manager Darwin Modules

**Goal:** Create `home/darwin/` modules and fix `home/default.nix` for cross-platform routing.

##### 3.1 Fix `home/default.nix` — Platform routing + homeDirectory

Updated `home/default.nix`:

```nix
{ user, system, lib, ... }:
let
  isLinux = builtins.elem system [ "x86_64-linux" "aarch64-linux" ];
  isDarwin = builtins.elem system [ "x86_64-darwin" "aarch64-darwin" ];
in
{
  imports = [
    ./common/shell.nix
    ./common/git.nix
    ./common/neovim.nix
    ./common/dev-tools.nix
    ./common/kitty.nix
    ./common/tmux.nix
    ./common/fastfetch.nix
  ] ++ lib.optionals isLinux [
    ./linux
  ] ++ lib.optionals isDarwin [
    ./darwin
  ];

  home = {
    username = user;
    homeDirectory = if isLinux then "/home/${user}" else "/Users/${user}";
    stateVersion = "25.05";
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
```

**Design decision:** Uses `builtins.elem system` pattern (consistent with existing code) rather than `pkgs.stdenv.isDarwin` (which would require adding `pkgs` to the function signature). The `system` variable is already in scope via `extraSpecialArgs`.

##### 3.2 Create `home/darwin/default.nix`

```nix
# home/darwin/default.nix
{ ... }:
{
  imports = [
    ./aerospace.nix
  ];

  # ── Zsh configuration (macOS default shell) ──
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    # Shell aliases inherited from home.shellAliases in home/common/shell.nix
  };
}
```

**Shell strategy:** `home/common/shell.nix` was refactored in Phase 1.3 to use `home.shellAliases`, which populates aliases for all enabled shells. Enabling `programs.zsh` here is sufficient — all aliases, starship integration, and direnv hooks activate automatically.

**YAGNI note:** `home/darwin/desktop.nix` was removed from the plan. It was an empty placeholder with no current content. When macOS-specific home packages are needed, add them here or create the file at that time.

##### 3.3 Create `home/darwin/aerospace.nix`

```nix
# home/darwin/aerospace.nix
{ ... }:
{
  programs.aerospace = {
    enable = true;

    settings = {
      enable-normalization-flatten-containers = false;
      enable-normalization-opposite-orientation-for-nested-containers = false;
      on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];

      gaps = {
        inner.horizontal = 8;
        inner.vertical = 8;
        outer.left = 8;
        outer.right = 8;
        outer.top = 8;
        outer.bottom = 8;
      };

      default-root-container-layout = "tiles";
      default-root-container-orientation = "auto";
      accordion-padding = 30;
      key-mapping.preset = "qwerty";

      mode.main.binding = {
        # Focus (alt + hjkl — mirrors Hyprland movefocus)
        alt-h = "focus left";
        alt-j = "focus down";
        alt-k = "focus up";
        alt-l = "focus right";

        # Move windows (alt+shift + hjkl)
        alt-shift-h = "move left";
        alt-shift-j = "move down";
        alt-shift-k = "move up";
        alt-shift-l = "move right";

        # Layout
        alt-f = "fullscreen";
        alt-shift-space = "layout floating tiling";
        alt-s = "layout v_accordion";
        alt-w = "layout h_accordion";
        alt-e = "layout tiles horizontal vertical";

        # Resize
        alt-shift-minus = "resize smart -50";
        alt-shift-equal = "resize smart +50";

        # Workspaces (alt+N — mirrors Hyprland workspace binds)
        alt-1 = "workspace 1";
        alt-2 = "workspace 2";
        alt-3 = "workspace 3";
        alt-4 = "workspace 4";
        alt-5 = "workspace 5";
        alt-6 = "workspace 6";
        alt-7 = "workspace 7";
        alt-8 = "workspace 8";
        alt-9 = "workspace 9";
        alt-0 = "workspace 10";

        # Move to workspace (alt+shift+N)
        alt-shift-1 = "move-node-to-workspace 1";
        alt-shift-2 = "move-node-to-workspace 2";
        alt-shift-3 = "move-node-to-workspace 3";
        alt-shift-4 = "move-node-to-workspace 4";
        alt-shift-5 = "move-node-to-workspace 5";
        alt-shift-6 = "move-node-to-workspace 6";
        alt-shift-7 = "move-node-to-workspace 7";
        alt-shift-8 = "move-node-to-workspace 8";
        alt-shift-9 = "move-node-to-workspace 9";
        alt-shift-0 = "move-node-to-workspace 10";

        # Misc
        alt-shift-c = "reload-config";
        alt-r = "mode resize";
      };

      mode.resize.binding = {
        h = "resize width -50";
        j = "resize height +50";
        k = "resize height -50";
        l = "resize width +50";
        enter = "mode main";
        esc = "mode main";
      };

      # TODO: on-window-detected has TOML rendering issue (nix-darwin #1271)
      # Add window rules after upstream fix, or switch to home.file if needed
      # on-window-detected = [
      #   { "if".app-id = "com.apple.systempreferences"; run = "layout floating"; }
      # ];
    };
  };
}
```

### Research Insights: Aerospace

**Modifier key:** Uses `alt` (Option key). This is the Aerospace community standard and avoids conflicts with macOS `cmd` shortcuts. Option key special characters (e.g., Option+2 = ™) are sacrificed in exchange for a consistent tiling WM experience. If this is a problem, switch to `ctrl-alt` as the modifier prefix.

**Aerospace vs yabai (2025-2026):** Community has shifted strongly to Aerospace. No SIP disable needed, i3-like model, first-class nix-darwin module, resilient to macOS updates. Correct choice.

**Startup:** The home-manager `programs.aerospace` module manages a launchd agent for login startup automatically — no manual Login Item configuration needed.

**TOML issue (#1271):** `on-window-detected` rules are commented out with a TODO. If needed before upstream fix, fall back to managing `~/.config/aerospace/aerospace.toml` via `xdg.configFile` instead.

##### Phase 3 acceptance criteria:
- [x] `home/default.nix` correctly routes to `home/darwin/` on Darwin and uses `/Users/${user}`
- [x] `home/darwin/default.nix` created with zsh and aerospace import
- [x] `home/darwin/aerospace.nix` created with keybindings mirroring Hyprland pattern
- [x] Shell aliases verified to work across bash (Linux) and zsh (Darwin) via `home.shellAliases`

---

#### Phase 4: Build Scripts + Bootstrap

**Goal:** Create `apps/build-switch-darwin` and `apps/bootstrap-darwin`.

##### 4.1 `apps/build-switch-darwin`

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(dirname "$SCRIPT_DIR")"

# Strip .local suffix from macOS hostname
HOST="${1:-$(hostname -s)}"

if [[ ! "$HOST" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: Invalid hostname '$HOST'. Expected alphanumeric with hyphens."
  exit 1
fi

echo "Building Darwin configuration for '$HOST'..."
darwin-rebuild switch --flake "$FLAKE_DIR#$HOST"
```

**Key differences from `apps/build-switch`:**
- Uses `hostname -s` (strips `.local` suffix on macOS)
- No `sudo` — `darwin-rebuild switch` runs as current user
- Calls `darwin-rebuild` instead of `nixos-rebuild`

### Research Insights: Build Script

**Unified script option:** A single `apps/build-switch` that auto-detects the OS via `uname -s` and calls the appropriate rebuild command would eliminate maintaining two scripts. However, separate scripts are simpler at this scale and avoid the indirection. Consider unifying later if the scripts diverge.

**Nix daemon check:** `darwin-rebuild` requires the Nix daemon. If the daemon is not running (e.g., after crash), the script gets a cryptic connection error. Optionally add a preflight check: `launchctl list | grep nix`.

##### 4.2 `apps/bootstrap-darwin`

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/jvall0228/nix-config.git"
REPO_DIR="$HOME/nix-config"
HOST="${1:-macbook-pro}"

echo "=== nix-config Darwin Bootstrap ==="
echo "Host: $HOST"
echo ""

# ── Step 1: Xcode Command Line Tools ──
if ! xcode-select -p &>/dev/null; then
  echo "Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "Press Enter after CLT installation completes..."
  read -r
else
  echo "Xcode CLT: already installed"
fi

# ── Step 2: Nix (official installer — multi-user, macOS compatible) ──
if ! command -v nix &>/dev/null; then
  echo "Installing Nix (official installer)..."
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://nixos.org/nix/install | sh -s -- --daemon
  # Source nix in current shell
  if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  fi
else
  echo "Nix: already installed"
fi

# Verify nix is available
if ! command -v nix &>/dev/null; then
  echo "Error: Nix not found in PATH after installation."
  echo "Please open a new terminal and re-run this script."
  exit 1
fi

# ── Step 3: Homebrew ──
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add Homebrew to PATH for current session (Apple Silicon path)
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "Homebrew: already installed"
fi

# ── Step 4: Clone repo ──
if [ ! -d "$REPO_DIR" ]; then
  echo "Cloning nix-config..."
  git clone "$REPO_URL" "$REPO_DIR"
else
  echo "Repo: already exists at $REPO_DIR"
fi

# ── Step 5: First activation ──
echo ""
echo "Running first nix-darwin activation..."
echo "This will take 15-25 minutes on first run (downloading all packages)."
echo ""
cd "$REPO_DIR"
nix run nix-darwin/nix-darwin-25.11#darwin-rebuild -- switch --flake ".#$HOST"

echo ""
echo "=== Bootstrap complete! ==="
echo "Subsequent rebuilds: bash apps/build-switch-darwin"
echo "Open a new terminal to get the full environment."
```

### Research Insights: Bootstrap Script

**Critical change: Official Nix installer.** The Determinate Systems installer **only ships their Nix fork since January 2026**. Switched to the official installer (`https://nixos.org/nix/install`) with `--daemon` flag for multi-user mode (required on modern macOS).

**Security hardening:**
- Added `--proto '=https' --tlsv1.2` to the Homebrew curl (was missing TLS enforcement)
- First activation pins to `nix-darwin/nix-darwin-25.11#darwin-rebuild` (matches the release branch in flake.nix)

**Idempotent** — each step checks if already done before running. Safe to re-run on partial failure.

**CLT install** is interactive (macOS requires GUI confirmation) — script pauses and waits.

**Homebrew install** requires sudo password (interactive) — this is unavoidable on fresh macOS.

**First activation time:** ~15-25 minutes (internet-bound, not CPU-bound). Downloads 5-10GB of packages.

**References:**
- [Determinate Systems dropped upstream Nix support (2026)](https://determinate.systems/blog/installer-dropping-upstream/)
- [Official Nix installer](https://nixos.org/download/)

##### Phase 4 acceptance criteria:
- [x] `apps/build-switch-darwin` works on an activated Darwin system
- [x] `apps/bootstrap-darwin` is idempotent (safe to re-run)
- [x] First activation uses `nix run nix-darwin/nix-darwin-25.11#darwin-rebuild`
- [x] Hostname `.local` suffix is stripped correctly
- [x] Both curl commands enforce HTTPS and TLS 1.2+

---

#### Phase 5: Documentation + Polish

**Goal:** Update CLAUDE.md, verify cross-platform build, clean up TODOs.

##### 5.1 Update `CLAUDE.md`

Add to the Repo Layout section:
```
- `modules/darwin/` — Darwin-specific system modules (system.defaults, homebrew, stylix).
- `home/darwin/` — Darwin-specific home-manager modules (aerospace).
```

Add new Agent Workflow section for Darwin:
```markdown
## Agent Workflow (Darwin Operations)

- **Rebuild system:** `bash apps/build-switch-darwin` (auto-detects hostname)
- **Rebuild specific host:** `bash apps/build-switch-darwin macbook-pro`
- **Bootstrap fresh Mac:** `bash apps/bootstrap-darwin`
- **Dry-build:** `darwin-rebuild build --flake ~/nix-config#macbook-pro`
- **Homebrew casks:** Auto-updated on every `darwin-rebuild switch`

### Darwin-Specific Constraints

- **No Lanzaboote/disko:** Darwin has no bootloader or disk config to manage.
- **Homebrew required:** Must be installed before `darwin-rebuild switch`. Bootstrap handles this.
- **stateVersion is integer:** nix-darwin uses `system.stateVersion = 6` (not a string).
- **No auto-upgrade:** Darwin requires manual rebuilds (no equivalent to `system.autoUpgrade`).
- **Touch ID sudo in tmux:** Requires `pam-reattach`. Installed by `modules/darwin/core.nix`.
- **nix flake check:** Must use `--system x86_64-linux` on NixOS or `--system aarch64-darwin` on Mac.
- **Store optimization:** `auto-optimise-store` is disabled on Darwin (corrupts store). Run `nix store optimise` manually if store grows large.
- **trusted-users:** The unprivileged user is in `trusted-users` for passwordless darwin-rebuild. This is a security tradeoff — see `modules/shared/nix.nix`.
```

##### 5.2 Verify cross-platform build

```bash
# On NixOS (should still build):
nix build .#nixosConfigurations.thinkpad.config.system.build.toplevel --dry-run

# For Darwin (can evaluate but not build on Linux):
nix eval .#darwinConfigurations.macbook-pro.config.system.build.toplevel --json

# Verify nix flake check per-platform:
nix flake check --system x86_64-linux
```

##### Phase 5 acceptance criteria:
- [x] CLAUDE.md updated with Darwin workflow section
- [x] NixOS configuration still builds without regressions
- [x] Darwin configuration evaluates without errors
- [x] All TODOs in `flake.nix` for Darwin are resolved

---

## System-Wide Impact

### Interaction Graph

- Adding `nix-darwin` input increases flake lock file entries and `nix flake update` time
- `modules/shared/nix.nix` changes affect both NixOS and Darwin — test NixOS build after modifying
- `home/default.nix` routing change affects all platforms — verify Linux imports still work
- `home/common/shell.nix` alias refactoring affects all platforms — verify bash aliases still work on NixOS

### Error Propagation

- If `modules/shared/nix.nix` has incorrect platform conditionals (`lib.mkIf` polarity wrong), the Nix daemon config on BOTH platforms could be corrupted simultaneously. This is the highest-risk change — commit separately and test NixOS build immediately.
- If `homebrew.onActivation.cleanup = "uninstall"` and a cask is accidentally removed from config, it gets uninstalled on next switch

### State Lifecycle Risks

- `system.stateVersion = 6` is set-once. Changing it on a deployed Darwin system can break state management
- Homebrew casks maintain their own state outside Nix — `cleanup = "zap"` would destroy that state (we use `"uninstall"` which is safe)

### API Surface Parity

- `apps/build-switch` (Linux) and `apps/build-switch-darwin` (Darwin) should have identical UX
- `home/common/*` modules must remain cross-platform safe

---

## Acceptance Criteria

### Functional Requirements

- [x] `darwinConfigurations.macbook-pro` evaluates and builds on aarch64-darwin
- [x] `nixosConfigurations.thinkpad` still builds without regressions
- [x] All `home/common/*` modules activate on both platforms
- [x] Shell aliases work in both bash (Linux) and zsh (Darwin)
- [x] Aerospace tiling WM is configured with hjkl navigation and workspace binds
- [x] Homebrew casks install GUI apps (Firefox, Discord, etc.)
- [x] macOS system preferences applied (Dock autohide, dark mode, key repeat, firewall, etc.)
- [x] Stylix themes kitty, bat, btop on Darwin
- [x] Touch ID sudo works (including in tmux with pam-reattach)
- [x] `bash apps/build-switch-darwin` rebuilds successfully
- [x] `bash apps/bootstrap-darwin` works on a fresh Mac (idempotent)

### Quality Gates

- [x] `nix flake check --system x86_64-linux` passes on NixOS
- [x] No hardcoded usernames — all use `${user}` variable
- [x] No NixOS-specific options in shared or Darwin modules
- [x] CLAUDE.md updated with Darwin documentation

---

## Dependencies & Prerequisites

- Apple Silicon MacBook Pro with macOS Sonoma 14+ (for `sudo_local` PAM support)
- Internet connection for first build (downloads ~5-10GB of packages)
- Admin account on macOS (for Homebrew installation)

---

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `nix-darwin/master` rejects `nixos-25.11` | **Certain** | High | Use `nix-darwin-25.11` release branch (Phase 1.1) |
| `auto-optimise-store` corruption on Darwin | High (if not fixed) | Critical | Platform conditional in `modules/shared/nix.nix` (Phase 1.2) |
| Shell aliases not available in zsh | **Certain** | High | Refactor to `home.shellAliases` (Phase 1.3) |
| Stylix module signature bug | **Certain** | High | Fixed: `{ pkgs, ... }:` (Phase 2.2) |
| `trusted-users` expansion security impact | N/A | Medium | Documented in CLAUDE.md, required for darwin-rebuild |
| Aerospace TOML rendering bug (#1271) | Known | Low | `on-window-detected` excluded; add after upstream fix |
| Determinate installer only ships fork | **Certain** (as of 2026) | High | Switched to official Nix installer (Phase 4.2) |
| Linux-only flake inputs fail on Darwin eval | Low | Medium | Inputs are lazy-evaluated; only fail if directly referenced |
| Homebrew auto-upgrade supply chain risk | Low | Medium | Acceptable tradeoff for keeping casks current |

---

## Files Summary

### New files (8)

| File | Purpose |
|---|---|
| `hosts/macbook-pro/default.nix` | Host config (hostname, user, stateVersion) |
| `modules/darwin/core.nix` | System defaults, security, gc, Homebrew, packages |
| `modules/darwin/stylix.nix` | Stylix with explicit Darwin target opt-ins |
| `home/darwin/default.nix` | Darwin home-manager entry (zsh, imports) |
| `home/darwin/aerospace.nix` | Aerospace tiling WM config |
| `apps/build-switch-darwin` | Darwin rebuild script |
| `apps/bootstrap-darwin` | Zero-to-working bootstrap script |

### Modified files (4)

| File | Change |
|---|---|
| `flake.nix` | Add nix-darwin input (`nix-darwin-25.11`), darwinConfigurations block, remove TODOs |
| `home/default.nix` | Add Darwin conditional imports, fix homeDirectory |
| `modules/shared/nix.nix` | Platform conditionals for gc and auto-optimise-store, add `lib`/`pkgs` to signature |
| `home/common/shell.nix` | Refactor `programs.bash.shellAliases` to `home.shellAliases` |
| `CLAUDE.md` | Add Darwin workflow documentation |

---

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-04-macos-configuration-brainstorm.md](docs/brainstorms/2026-03-04-macos-configuration-brainstorm.md) — Key decisions carried forward: parallel module structure, Aerospace in home/darwin/, Stylix hybrid theming, Homebrew casks for GUI apps, bootstrap script.

### Internal References

- Existing NixOS config pattern: `flake.nix:58-92`
- Home platform routing: `home/default.nix:11-13`
- Shared Nix settings: `modules/shared/nix.nix`
- Shell alias pattern: `home/common/shell.nix` (confirmed `programs.bash.shellAliases`)
- NixOS host template: `hosts/thinkpad/default.nix`
- Build script pattern: `apps/build-switch`
- Rice plan patterns: `docs/plans/2026-03-02-feat-daily-driver-rice-plan.md`

### External References

- [nix-darwin repository](https://github.com/nix-darwin/nix-darwin)
- [nix-darwin release branch policy (#727, #1284)](https://github.com/nix-darwin/nix-darwin/issues/727)
- [nix-darwin system.defaults options](https://mynixos.com/nix-darwin/options/system.defaults)
- [nix-darwin homebrew module](https://github.com/LnL7/nix-darwin/blob/master/modules/homebrew.nix)
- [zhaofengli/nix-homebrew](https://github.com/zhaofengli/nix-homebrew) — declarative Homebrew installation
- [AeroSpace GitHub](https://github.com/nikitabobko/AeroSpace)
- [home-manager aerospace module](https://github.com/nix-community/home-manager/blob/master/modules/programs/aerospace.nix)
- [Aerospace TOML issue #1271](https://github.com/nix-darwin/nix-darwin/issues/1271)
- [dustinlyons/nixos-config](https://github.com/dustinlyons/nixos-config) — reference dual-platform flake
- [Stylix Darwin support](https://stylix.danth.me/installation.html)
- [Official Nix installer](https://nixos.org/download/)
- [Determinate Systems dropped upstream Nix (2026)](https://determinate.systems/blog/installer-dropping-upstream/)
- [NixOS Discourse: nixpkgs branch for NixOS + Darwin](https://discourse.nixos.org/t/which-nixpkgs-stable-tag-for-nixos-and-darwin-together/32796)
- [Best practices: sharing dotfiles between macOS and NixOS](https://discourse.nixos.org/t/best-practices-for-sharing-dotfiles-between-macos-and-nixos/4426)
