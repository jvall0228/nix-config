# Deployment Checklist: Add macOS Darwin Configuration

**Plan Reference:** `docs/plans/2026-03-04-feat-macos-darwin-configuration-plan.md`

**Scope:** First-time activation of a nix-darwin system (`darwinConfigurations.macbook-pro`) on Apple Silicon MacBook Pro. This touches shared Nix configuration, adds new modules, and requires new bootstrap/rebuild scripts.

**Risk Level:** HIGH — Shared module changes affect both NixOS and Darwin platforms. Homebrew state management and bootstrap idempotency are critical for fresh macOS activation.

---

## Pre-Activation Verification (Before Any Changes)

Start with system baseline and NixOS validation.

### 1.1 Validate Current NixOS Configuration

**Status:** Current state on ThinkPad should be unchanged (baseline for regression testing).

```bash
# Run on ThinkPad (NixOS)
systemctl is-system-running
```

**Expected:** `running` or `degraded` (not `offline`)

### 1.2 Test Current NixOS Build

**CRITICAL:** Before modifying `modules/shared/nix.nix`, verify NixOS builds cleanly.

```bash
# Dry-run build to catch any immediate issues
nixos-rebuild dry-build --flake ~/nix-config#thinkpad
```

**Expected:** Completes without evaluation errors. Note the derivation hash:
```
these derivations will be built:
  /nix/store/...-nixos-system-thinkpad-25.05.drv
```

**Save this output.** After modifying `modules/shared/nix.nix`, the hash should change slightly due to config changes, but the *evaluation* should not error.

### 1.3 Verify Module Structure

Before adding new modules, check that the directory structure exists:

```bash
# Check that modules/darwin/ and home/darwin/ don't yet exist
[ ! -d ~/nix-config/modules/darwin ] && echo "OK: modules/darwin does not exist"
[ ! -d ~/nix-config/home/darwin ] && echo "OK: home/darwin does not exist"
[ ! -f ~/nix-config/apps/build-switch-darwin ] && echo "OK: build-switch-darwin does not exist"
[ ! -f ~/nix-config/apps/bootstrap-darwin ] && echo "OK: bootstrap-darwin does not exist"
```

**Expected:** All four files/directories should not exist yet.

---

## Phase 1: Shared Module Safety (Critical — Blocks Darwin)

The `modules/shared/nix.nix` change is the highest-risk modification because it affects BOTH NixOS and Darwin.

### Phase 1.1: Review Shared Module Changes

**Current state:** `/Users/javels/nix-config/modules/shared/nix.nix`

```nix
# Current code that needs change:
nix.settings = {
  auto-optimise-store = true;  # ← BREAKS Darwin
  ...
};

nix.gc = {
  automatic = true;
  dates = "weekly";  # ← NixOS-specific syntax
  ...
};
```

**Issue:** Darwin uses `nix.gc.interval` (launchd) instead of `dates` (systemd). `auto-optimise-store = true` corrupts the Darwin Nix store due to inode differences.

### Phase 1.2: Apply Shared Module Conditional Fix

Update `/Users/javels/nix-config/modules/shared/nix.nix`:

1. Add `lib` and `pkgs` to function signature:
   ```nix
   # OLD: { user, ... }:
   # NEW:
   { user, lib, pkgs, ... }:
   ```

2. Make `auto-optimise-store` platform-conditional:
   ```nix
   nix.settings = {
     ...
     auto-optimise-store = !pkgs.stdenv.isDarwin;  # false on Darwin, true on Linux
     ...
   };
   ```

3. Gate `nix.gc.dates` to NixOS only:
   ```nix
   nix.gc = lib.mkIf pkgs.stdenv.isLinux {
     automatic = true;
     dates = "weekly";
     options = "--delete-older-than 30d";
   };
   ```

**Exact replacement:**
- Old string: `nix.settings = {\n    experimental-features = [ "nix-command" "flakes" ];\n    auto-optimise-store = true;`
- New string: Add `lib, pkgs` to signature, change `auto-optimise-store = !pkgs.stdenv.isDarwin;`, wrap `nix.gc` block with `lib.mkIf pkgs.stdenv.isLinux {` and `};`

### Phase 1.3: Test NixOS After Shared Module Change

**CRITICAL VALIDATION:** The NixOS build must still work.

```bash
# On ThinkPad or build machine
nixos-rebuild dry-build --flake ~/nix-config#thinkpad
```

**Expected:**
- Evaluation completes without errors
- Derivation hash differs from pre-change (due to config changes)
- No warnings about undefined `lib` or `pkgs`

**If this fails:** Rollback `modules/shared/nix.nix` immediately. Do not proceed.

### Phase 1.4: Commit Shared Module Fix

Once NixOS passes, commit the shared module change:

```bash
cd ~/nix-config
git add modules/shared/nix.nix
git commit -m "fix: platform-conditional gc and auto-optimise-store in shared nix module"
```

**This is a separate commit** from Darwin-specific code, so we can isolate any regressions.

---

## Phase 2: Add nix-darwin Input & Flake Structure

### Phase 2.1: Add nix-darwin Input

Edit `flake.nix` inputs section:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

  home-manager = { ... };

  # ADD THIS:
  nix-darwin = {
    url = "github:nix-darwin/nix-darwin";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # ... rest of inputs
};
```

Also update the `outputs` destructuring:

```nix
# OLD: outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ..., walker, ags, astal, ... }@inputs:
# NEW: outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ..., walker, ags, astal, nix-darwin, ... }@inputs:
```

### Phase 2.2: Verify Flake Lock After Input Addition

```bash
cd ~/nix-config
nix flake update
git diff flake.lock
```

**Expected:** `flake.lock` shows new entries for nix-darwin and its dependencies. Lines added: ~10-20.

### Phase 2.3: Test Flake Still Evaluates (Linux)

```bash
# Test that NixOS config still works
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel --json > /dev/null && echo "NixOS eval OK"
```

**Expected:** No errors. This proves adding `nix-darwin` input doesn't break existing Linux evaluation.

### Phase 2.4: Add darwinConfigurations Block (Minimal)

Edit `flake.nix` outputs section. Add after `nixosConfigurations.thinkpad` and before the Checks section:

```nix
# ── Darwin hosts ───────────────────────────────────────────
darwinConfigurations.macbook-pro = let system = "aarch64-darwin"; in nix-darwin.lib.darwinSystem {
  specialArgs = { inherit inputs user; unstable = unstableFor system; };
  modules = [
    { nixpkgs.hostPlatform = system; }
    ./hosts/macbook-pro/default.nix
    ./modules/shared/nix.nix
    ./modules/darwin/core.nix
    ./modules/darwin/homebrew.nix
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

**Also remove the Darwin-related TODOs:**
- Line 99: `# TODO: Add darwinConfigurations...`
- Line 101: `# TODO: Add apps.aarch64-darwin...`

### Phase 2.5: Test Darwin Flake Evaluation (Dry, No Build)

```bash
# Can evaluate on any platform, won't build on Linux (expected)
nix eval .#darwinConfigurations.macbook-pro.config.system.build.toplevel --json > /dev/null && echo "Darwin eval OK"
```

**Expected:** Evaluation completes without errors. May show warnings about Linux-only options, but should not fail.

**If evaluation fails:** Check that all imported modules (core.nix, homebrew.nix, stylix.nix) exist (dummy files are OK for now).

---

## Phase 3: Create Darwin System Modules

Create these files with the exact content from the plan. Each must be testable before moving to the next.

### Phase 3.1: Create `hosts/macbook-pro/default.nix`

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

**Validation:**
```bash
nix eval .#darwinConfigurations.macbook-pro.config.networking.hostName --json
# Expected: "macbook-pro"
```

### Phase 3.2: Create `modules/darwin/core.nix`

Create file with exact content from plan (lines 186-268). Key sections:
- `nix.gc.interval` (Darwin-specific launchd syntax)
- `system.defaults` (Dock, Finder, NSGlobalDomain, etc.)
- `security.pam.services.sudo_local.touchIdAuth = true`
- `programs.zsh.enable = true`
- `environment.systemPackages` with `pam-reattach`

**Validation:**
```bash
nix eval .#darwinConfigurations.macbook-pro.config.nix.gc.interval --json
# Expected: [{ Hour = 4; Minute = 0; }] (or similar launchd syntax)
```

### Phase 3.3: Create `modules/darwin/homebrew.nix`

Create file with exact content from plan (lines 276-310). Core:
- `homebrew.enable = true`
- `onActivation.cleanup = "uninstall"` (safe: removes unlisted casks, not data)
- Cask list: `[ "firefox" "1password" "discord" ... ]`
- `brews = [ "mas" ]` (Mac App Store CLI)

**Note:** This can only be fully validated when run on actual macOS.

**Validation (dry):**
```bash
nix eval .#darwinConfigurations.macbook-pro.config.homebrew.enable --json
# Expected: true
```

### Phase 3.4: Create `modules/darwin/stylix.nix`

Create file with exact content from plan (lines 324-354). Key:
- `autoEnable = false` (critical: prevents errors from nonexistent Darwin targets)
- `targets.kitty.enable = true` (and btop, bat)
- Base16 scheme path (same as NixOS)
- Font paths correct relative to `modules/darwin/`

**Validation:**
```bash
nix eval .#darwinConfigurations.macbook-pro.config.stylix.autoEnable --json
# Expected: false
```

### Phase 3.5: Verify All Module Imports Work

```bash
nix eval .#darwinConfigurations.macbook-pro --json > /dev/null && echo "All Darwin modules load"
```

**Expected:** No errors about missing modules or undefined references.

---

## Phase 4: Create Home-Manager Darwin Modules

### Phase 4.1: Update `home/default.nix` for Platform Routing

Replace the file with the version from the plan (lines 388-418):

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

**Critical changes:**
1. Add `system` parameter (from `extraSpecialArgs` in flake.nix)
2. Define `isLinux` and `isDarwin` helpers
3. Import `./darwin` conditionally (will fail on Linux if doesn't exist yet)
4. Set `homeDirectory` conditionally

**Validation (on Linux):**
```bash
nix eval .#nixosConfigurations.thinkpad.config.home-manager.users.javels.home.homeDirectory --json
# Expected: "/home/javels"
```

### Phase 4.2: Create `home/darwin/default.nix`

```nix
# home/darwin/default.nix
{ pkgs, ... }:
{
  imports = [
    ./aerospace.nix
    ./desktop.nix
  ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
  };
}
```

**Design note:** macOS defaults to zsh. Shell aliases from `home/common/shell.nix` are inherited if they use `home.shellAliases` (platform-neutral) rather than `programs.bash.shellAliases` (bash-only).

**TODO during implementation:** Verify `home/common/shell.nix` uses `home.shellAliases`.

### Phase 4.3: Create `home/darwin/aerospace.nix`

Copy exact content from plan (lines 459-549). Key sections:
- Keybindings: alt+hjkl for navigation (mirrors Hyprland pattern)
- Workspaces: alt+1..9, alt+shift+1..9 for move-to-workspace
- Gaps and layout options
- `on-window-detected` is commented out (upstream bug #1271)

**Validation:**
```bash
nix eval '.#darwinConfigurations.macbook-pro.config.home-manager.users.javels.programs.aerospace.enable' --json
# Expected: true
```

### Phase 4.4: Create `home/darwin/desktop.nix`

```nix
# home/darwin/desktop.nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # macOS-specific CLI tools go here
    # GUI apps are in modules/darwin/homebrew.nix
  ];
}
```

Intentionally minimal. GUI apps are in Homebrew casks.

### Phase 4.5: Verify Home-Manager Darwin Config

```bash
# Test evaluation of full Darwin config
nix eval .#darwinConfigurations.macbook-pro.config.home-manager.users.javels.home.packages --json > /dev/null && echo "Home config loads"
```

**Expected:** No errors.

---

## Phase 5: Build Scripts

### Phase 5.1: Create `apps/build-switch-darwin`

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
- No `sudo` (darwin-rebuild runs as user)
- Uses `hostname -s` (strips `.local` on macOS)
- Calls `darwin-rebuild` not `nixos-rebuild`

**Make executable:**
```bash
chmod +x ~/nix-config/apps/build-switch-darwin
```

### Phase 5.2: Create `apps/bootstrap-darwin`

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

# ── Step 2: Nix ──
if ! command -v nix &>/dev/null; then
  echo "Installing Nix (Determinate Systems installer)..."
  curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix | sh -s -- install
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
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
echo "This will take a while on first run (downloading all packages)."
echo ""
cd "$REPO_DIR"
nix run nix-darwin#darwin-rebuild -- switch --flake ".#$HOST"

echo ""
echo "=== Bootstrap complete! ==="
echo "Subsequent rebuilds: bash apps/build-switch-darwin"
echo "Open a new terminal to get the full environment."
```

**Make executable:**
```bash
chmod +x ~/nix-config/apps/bootstrap-darwin
```

**Key design:**
- Idempotent (safe to re-run)
- First activation uses `nix run nix-darwin#darwin-rebuild` (flake-based, no install needed)
- Interactive steps (CLT, Homebrew) require manual intervention
- Sources nix-daemon.sh so subsequent steps work in same shell

### Phase 5.3: Test Scripts Exist and Are Executable

```bash
[ -x ~/nix-config/apps/build-switch-darwin ] && echo "build-switch-darwin is executable"
[ -x ~/nix-config/apps/bootstrap-darwin ] && echo "bootstrap-darwin is executable"
```

---

## Phase 6: Final Validation Before Activation

### Phase 6.1: Verify All Files Created

```bash
test -f ~/nix-config/hosts/macbook-pro/default.nix && echo "✓ hosts/macbook-pro/default.nix"
test -f ~/nix-config/modules/darwin/core.nix && echo "✓ modules/darwin/core.nix"
test -f ~/nix-config/modules/darwin/homebrew.nix && echo "✓ modules/darwin/homebrew.nix"
test -f ~/nix-config/modules/darwin/stylix.nix && echo "✓ modules/darwin/stylix.nix"
test -f ~/nix-config/home/darwin/default.nix && echo "✓ home/darwin/default.nix"
test -f ~/nix-config/home/darwin/aerospace.nix && echo "✓ home/darwin/aerospace.nix"
test -f ~/nix-config/home/darwin/desktop.nix && echo "✓ home/darwin/desktop.nix"
test -x ~/nix-config/apps/build-switch-darwin && echo "✓ apps/build-switch-darwin (executable)"
test -x ~/nix-config/apps/bootstrap-darwin && echo "✓ apps/bootstrap-darwin (executable)"
```

**Expected:** All lines should print.

### Phase 6.2: Validate NixOS Still Builds (Regression Test)

**CRITICAL:** Ensure the shared module changes don't break NixOS.

```bash
# On ThinkPad or build system
nixos-rebuild dry-build --flake ~/nix-config#thinkpad 2>&1 | tee ~/nix-rebuild-test.log
```

**Expected:**
- No evaluation errors
- Output ends with: `these derivations will be built: /nix/store/...-nixos-system-thinkpad-25.05.drv`

**If failed:** Examine log, likely causes:
- `modules/shared/nix.nix` conditionals have typo (check `lib.mkIf` syntax)
- `modules/shared/nix.nix` missing `lib` in function signature
- NixOS module uses undefined variable

### Phase 6.3: Full Flake Check

```bash
cd ~/nix-config
nix flake check
```

**Expected:** Either:
- `Checks: 1 passed` (only NixOS check exists for now)
- Any pre-existing check passes

**Note:** Darwin checks cannot run on Linux, so they're skipped.

### Phase 6.4: Commit All New Files

```bash
cd ~/nix-config

# Stage everything
git add \
  flake.nix \
  home/default.nix \
  hosts/macbook-pro/default.nix \
  modules/darwin/core.nix \
  modules/darwin/homebrew.nix \
  modules/darwin/stylix.nix \
  home/darwin/default.nix \
  home/darwin/aerospace.nix \
  home/darwin/desktop.nix \
  apps/build-switch-darwin \
  apps/bootstrap-darwin

# Review
git status

# Commit (can be one commit since changes are cohesive)
git commit -m "feat: add macOS Darwin configuration with nix-darwin and home-manager

- Add nix-darwin input and darwinConfigurations.macbook-pro
- Create modules/darwin/* (core.nix, homebrew.nix, stylix.nix) for system config
- Create home/darwin/* (default.nix, aerospace.nix, desktop.nix) for user config
- Fix home/default.nix for platform routing (/Users vs /home)
- Fix modules/shared/nix.nix with platform conditionals (gc, auto-optimise-store)
- Add apps/build-switch-darwin and apps/bootstrap-darwin scripts
- Targets Apple Silicon MacBook Pro (aarch64-darwin) with Aerospace tiling WM"
```

---

## First Activation on macOS (The Critical Flow)

This section covers what happens when someone runs the bootstrap script on a fresh MacBook Pro.

### Activation 1: Bootstrap Idempotency (Edge Cases)

The `apps/bootstrap-darwin` script is designed to be idempotent. Test each edge case:

**Scenario A: Fresh Mac (all tools missing)**
```bash
# On fresh Mac from Sonoma 14+
bash ~/Downloads/bootstrap-darwin.sh
```

Expected flow:
1. ✓ Xcode CLT install dialog appears → user clicks Install → script waits for completion
2. ✓ Nix installer runs
3. ✓ nix-daemon.sh sourced, `nix` now available
4. ✓ Homebrew installer runs (may ask for sudo password)
5. ✓ repo cloned
6. ✓ `nix run nix-darwin#darwin-rebuild` completes first activation
7. ✓ User sees: "Bootstrap complete! Subsequent rebuilds: bash apps/build-switch-darwin"

**Scenario B: Xcode CLT already installed**
```bash
# Script should skip step 1
xcode-select -p  # Prints /Applications/Xcode.app/...
bash ~/Downloads/bootstrap-darwin.sh
```

Expected: Script prints "Xcode CLT: already installed" and skips to Nix.

**Scenario C: Nix already installed**
```bash
# Script should skip Nix, verify it's in PATH
which nix
bash ~/Downloads/bootstrap-darwin.sh
```

Expected: Script prints "Nix: already installed" and skips to Homebrew.

**Scenario D: Repo already cloned**
```bash
# If ~/nix-config exists, script should skip clone
bash ~/nix-config/apps/bootstrap-darwin
```

Expected: Script prints "Repo: already exists at $HOME/nix-config" and skips to first activation.

**Scenario E: First activation fails partway**
```bash
# E.g., network timeout during package download
# User runs bootstrap again
bash ~/nix-config/apps/bootstrap-darwin
```

Expected: Skips installed tools, continues from where it stopped (first activation will resume/retry).

### Activation 2: First darwin-rebuild switch Specifics

When `nix run nix-darwin#darwin-rebuild -- switch --flake ".#macbook-pro"` runs:

1. **Downloads all packages** for macOS (kitty, neovim, tmux, etc.) — ~5-10 GB on first run
2. **Creates directories:**
   - `/Users/javels/.config/` (home-manager)
   - `/nix/store/` (Nix packages)
   - `/etc/nix/nix.conf` (Nix config from `modules/shared/nix.nix`)
3. **Installs Homebrew casks** — first run will download Firefox, Discord, Slack, 1Password, Spotify, Obsidian, VSCode, Telegram, Raycast via `homebrew.onActivation.upgrade = true`
4. **Sets system.defaults** — Dock autohide, key repeat, dark mode, etc.
5. **Enables Touch ID for sudo** via PAM config
6. **Configures Aerospace** — Launchd agent auto-starts on login
7. **Loads Stylix theming** — kitty, bat, btop get Tokyo Night Dark theme

### Activation 3: Rollback Strategy (If Activation Fails)

**Can we roll back?**

**YES, partially:**
- Darwin system can be rolled back via `darwin-rebuild --rollback`
- Homebrew casks can be manually uninstalled if needed
- `home-manager` config can be rolled back (uses `backupFileExtension = "backup"`)

**Data safety:**
- No destructive operations in default configs
- `homebrew.onActivation.cleanup = "uninstall"` only removes *unlisted* casks (safe)
- Nix store remains untouched (can do `nix store gc`)

**Actual rollback steps if needed:**

```bash
# If darwin-rebuild switch fails mid-way:

# 1. Check what went wrong
darwin-rebuild dry-build --flake ~/nix-config#macbook-pro 2>&1 | tail -50

# 2. Rollback to last working generation
darwin-rebuild --rollback

# 3. Fix the issue in your config
# (e.g., typo in Aerospace keybinding, missing Homebrew cask)

# 4. Try again
darwin-rebuild switch --flake ~/nix-config#macbook-pro
```

**If Homebrew gets into a bad state:**
```bash
# Don't use `brew cleanup -s` (safe cleanup)
# Avoid `brew zap` (destructive)

# Check what's installed:
brew list --cask

# If a cask fails to install during switch:
# 1. Check the log for the error
# 2. Manually fix (e.g., `brew install firefox --force`)
# 3. Re-run darwin-rebuild switch
```

### Activation 4: Known Issues & Workarounds

**Issue 1: Touch ID doesn't work in tmux immediately after activation**

**Cause:** PAM config for `pam-reattach` may not be fully applied until next login.

**Workaround:**
```bash
# After first activation, log out and log back in
# Or reload tmux:
tmux kill-server
tmux new-session
```

**Issue 2: Aerospace bindings feel unresponsive on first run**

**Cause:** Aerospace daemon may not be fully started.

**Workaround:**
```bash
# Reload Aerospace config
alt+shift+c  # reload-config binding in aerospace.nix

# Or restart via:
launchctl stop com.nikitabobko.AeroSpace
launchctl start com.nikitabobko.AeroSpace
```

**Issue 3: Homebrew cask installation times out**

**Cause:** First build downloads many large casks over network.

**Mitigation:** Plan for 30-60 minutes on first activation. Check network connection.

---

## Post-Activation Verification (Within 5 Minutes)

After `darwin-rebuild switch` completes successfully.

### Verify 1: System Activation Success

```bash
# Check that darwin-rebuild completed
echo $?
# Expected: 0 (exit code success)

# Verify configuration is active
system_profiler SPSoftwareDataType | grep "System Version"
# Should show macOS Sonoma or later
```

### Verify 2: Core System Defaults Applied

```bash
# Check Dock autohide
defaults read com.apple.dock autohide
# Expected: 1

# Check dark mode
defaults read -g AppleInterfaceStyle
# Expected: Dark

# Check key repeat
defaults read -g KeyRepeat
# Expected: 2

# Check Touch ID for sudo
cat /etc/pam.d/sudo_local | grep -c "pam_reattach.so"
# Expected: 1
```

### Verify 3: Nix Configuration Applied

```bash
# Check Nix daemon config
cat /etc/nix/nix.conf | grep -c "auto-optimise-store"
# Expected: 1 line present, value should be false

# Check nix-darwin gc interval
defaults read /Library/Preferences/com.apple.system.preferences.plist | grep -c "nix.gc"
# (or check launchd config)

# Verify Nix paths
which nix
nix --version
```

### Verify 4: Homebrew State

```bash
# List installed casks
brew list --cask
# Expected: firefox, 1password, discord, slack, spotify, obsidian, vscode, telegram, raycast, etc.

# Check Homebrew is working
brew doctor
# Expected: No major errors (some warnings about third-party tools are OK)
```

### Verify 5: Home-Manager Configuration

```bash
# Check home-manager generation
home-manager generations
# Expected: Shows current generation

# Check shell is zsh
echo $SHELL
# Expected: /run/current-system/sw/bin/zsh or /bin/zsh

# Verify neovim is available
which nvim
nvim --version | head -1
# Expected: NVIM v...
```

### Verify 6: Aerospace Tiling WM

```bash
# Check Aerospace is running
ps aux | grep -i aerospace | grep -v grep
# Expected: Shows `aerospace` process

# Check config loaded
cat ~/.config/aerospace/aerospace.toml | head -5
# Expected: Shows Aerospace config

# Test a keybinding (open Terminal)
# Press: opt-j to focus down, opt-1 to switch workspace 1
# The window should move/focus
```

### Verify 7: Stylix Theming

```bash
# Check kitty is themed
cat ~/.config/kitty/colors.conf | head -3
# Expected: Shows color definitions from Tokyo Night Dark

# Verify bat is themed
bat --theme Tokyo\ Night\ Dark /etc/profile 2>/dev/null | head -3
# Expected: Syntax highlighting in Tokyo Night Dark

# Check btop has theme
cat ~/.config/btop/btop.conf | grep -i theme
# Expected: Shows Tokyo Night Dark
```

### Verify 8: Shell Aliases Work

```bash
# Test if common aliases are available
alias | grep -E "ll|la|ls"
# Expected: Shows shell aliases from home/common/shell.nix

# Test one explicitly
ll /tmp
# Expected: long format directory listing
```

### Verify 9: Touch ID for sudo

```bash
# Test that Touch ID works
sudo -v
# You should be prompted to authenticate with Touch ID, not password
# (may need to retry if first activation was recent)

# In tmux:
tmux new-session -d -s test
tmux send-keys -t test "sudo -v" Enter
# Touch ID should work (with pam-reattach)
```

### Verify 10: Critical Data Invariants

| Check | Query | Expected |
|-------|-------|----------|
| User home correct | `echo $HOME` | `/Users/javels` |
| Hostname set | `hostname` | `macbook-pro` (or `.local` variant) |
| Nix store writable | `touch /nix/var/test && rm /nix/var/test` | No permission error |
| Homebrew clean | `brew list --cask \| wc -l` | ≥ 9 (casks installed) |
| Config backed up | `ls -la ~/.config/*.backup 2>/dev/null \| wc -l` | ≥ 0 (home-manager backup extension) |

---

## Post-Activation Monitoring (24 Hours)

### Monitoring 1: At +1 Hour

After activation, open Activity Monitor and check:

```bash
# CPU usage of key daemons (should be low after initial setup)
ps aux | grep -E "nix|homebrew|aerospace" | head -5
# Expected: Low CPU, normal processes

# Disk space after all packages downloaded
df -h / | tail -1
# Note the value for comparison (should stabilize)

# Check for any errors in system logs
log show --predicate 'level >= warning' --last 1h | tail -20
# Look for "nix-darwin", "AeroSpace", "homebrew" errors
# Some warnings are expected; critical errors are not
```

### Monitoring 2: At +4 Hours

Check if any background processes are stuck:

```bash
# Look for hung builds or downloads
ps aux | grep -E "nix|brew" | grep -v grep
# Expected: Most should have exited; if dozens of processes remain, something hung

# Check available disk space
df -h /
# Expected: At least 10 GB free (after build/caches)

# Verify nix-collect-garbage is scheduled
launchctl list | grep nix
# Expected: Shows nix-gc launch agent
```

### Monitoring 3: At +24 Hours

Verify system stability over time:

```bash
# Check system uptime (should show > 1 day without issues)
uptime

# Verify no critical logs
log show --predicate 'eventType == "logEvent" AND level == "Critical"' --last 24h | wc -l
# Expected: 0

# Confirm Homebrew cask auto-update didn't break anything
brew outdated
# No errors expected

# Test a full rebuild (should complete in ~5-10 min on stable config)
time bash ~/nix-config/apps/build-switch-darwin
# Expected: Completes without errors, takes << first activation time
```

---

## Regression Testing: Ensure NixOS Unaffected

Run these checks after Darwin activation to prove NixOS still works.

### Regression 1: NixOS Builds (On Linux)

```bash
# On ThinkPad or build machine
nixos-rebuild dry-build --flake ~/nix-config#thinkpad
```

**Expected:** Completes without errors. Derivation hash will differ from initial baseline (due to potential nixpkgs updates), but no *evaluation* errors.

### Regression 2: Home-Manager on NixOS

```bash
# On ThinkPad, test home-manager build
home-manager switch -b backup --flake ~/nix-config#thinkpad
```

**Expected:** Completes, shows home-manager generation. Shell aliases, neovim, git config still present.

### Regression 3: Shared Module Logic

```bash
# Verify nix.gc is still scheduled on NixOS
sudo systemctl status nix-gc.timer
# Expected: enabled and active

# Verify auto-optimise-store is still true on NixOS
cat /etc/nix/nix.conf | grep auto-optimise-store
# Expected: shows "auto-optimise-store = true" (not "false")
```

---

## Emergency Procedures

### If First Activation Fails

**Symptom:** `darwin-rebuild switch` fails partway through.

1. **Examine the error:**
   ```bash
   darwin-rebuild switch --flake ~/nix-config#macbook-pro 2>&1 | tail -100 > ~/failure.log
   cat ~/failure.log
   ```

2. **Likely causes:**
   - Missing module file (e.g., `modules/darwin/core.nix` doesn't exist) → Create it
   - Typo in `flake.nix` (syntax error) → Check Nix syntax
   - Homebrew cask name invalid → Check `modules/darwin/homebrew.nix` cask list
   - Network timeout → Retry (packages will resume)

3. **Rollback to last working:**
   ```bash
   darwin-rebuild --rollback
   ```

4. **Verify rollback worked:**
   ```bash
   system_profiler SPSoftwareDataType
   # Should show previous system version
   ```

### If Shared Module Breaks NixOS

**Symptom:** NixOS no longer builds after shared module change.

1. **Identify the breakage:**
   ```bash
   nixos-rebuild dry-build --flake ~/nix-config#thinkpad 2>&1 | grep -A 5 "error:"
   ```

2. **Roll back the shared module:**
   ```bash
   git log --oneline modules/shared/nix.nix | head -5
   git show HEAD:modules/shared/nix.nix > /tmp/nix.nix.current
   git show HEAD~1:modules/shared/nix.nix > /tmp/nix.nix.previous
   # Compare
   diff /tmp/nix.nix.{previous,current}
   ```

3. **Revert if necessary:**
   ```bash
   git checkout HEAD~1 -- modules/shared/nix.nix
   git commit -m "revert: shared nix module broke NixOS"
   ```

4. **Re-test NixOS:**
   ```bash
   nixos-rebuild dry-build --flake ~/nix-config#thinkpad
   ```

### If Homebrew Gets Corrupted

**Symptom:** Homebrew casks fail to install or uninstall.

```bash
# Check Homebrew health
brew doctor

# If formula is broken:
brew tap-info homebrew/cask
brew update

# If a specific cask fails:
brew install --force firefox  # or whichever cask failed

# If cask list is inconsistent:
# Remove offending cask from modules/darwin/homebrew.nix
# Re-run: darwin-rebuild switch --flake ~/nix-config#macbook-pro
# (cleanup = "uninstall" will remove unlisted casks)
```

---

## Summary Checklist

**Copy this into your pre-activation notes on macOS:**

```
PRE-ACTIVATION:
[ ] NixOS build still passes on ThinkPad (regression test)
[ ] All Darwin module files created (9 files)
[ ] All app scripts executable
[ ] Git commits created
[ ] Network connection stable (5+ Mbps for package downloads)
[ ] At least 50 GB free disk space on MacBook Pro

DURING BOOTSTRAP:
[ ] Xcode CLT installed (interactive, ~10-20 min)
[ ] Nix installed (auto, ~5 min)
[ ] Homebrew installed (may prompt for password)
[ ] Repo cloned to ~/nix-config
[ ] First activation runs (`nix run nix-darwin#darwin-rebuild`)
[ ] Takes 30-60 min on first run (patience!)

AFTER ACTIVATION (5 MIN):
[ ] System defaults applied (Dock, dark mode, key repeat)
[ ] Homebrew casks installed (Firefox, Discord, Slack, etc.)
[ ] Home-manager config active (zsh, neovim, tmux, aliases)
[ ] Aerospace tiling WM running and responsive
[ ] Stylix theming applied (kitty, bat, btop)
[ ] Touch ID works for sudo
[ ] Shell aliases available (`ll`, `la`, etc.)

AT 24 HOURS:
[ ] No system crashes or hangs
[ ] Disk space stable
[ ] Homebrew auto-update completed without errors
[ ] Quick rebuild (bash apps/build-switch-darwin) completes in < 10 min

REGRESSION VALIDATION:
[ ] NixOS on ThinkPad still builds
[ ] home-manager switch on NixOS still works
[ ] nix.gc.dates="weekly" still present on NixOS (not "false")
[ ] auto-optimise-store=true still on NixOS (not "false")
```

---

## Critical Path (Minimal Checklist)

If time is limited, verify these before deployment:

1. ✅ `modules/shared/nix.nix` is platform-conditional (uses `lib.mkIf pkgs.stdenv.isLinux` for gc)
2. ✅ NixOS builds after shared module change (regression test)
3. ✅ All 9 Darwin module files exist and have correct content
4. ✅ `flake.nix` adds `nix-darwin` input and `darwinConfigurations.macbook-pro`
5. ✅ `home/default.nix` correctly routes to `home/darwin/` and uses `/Users/${user}`
6. ✅ `apps/bootstrap-darwin` is idempotent (safe to re-run on fresh Mac)
7. ✅ Git commits created and pushed
8. ✅ First activation uses `nix run nix-darwin#darwin-rebuild` (flake-based)
9. ✅ Post-activation verification passes (system.defaults, Homebrew casks, home-manager)
10. ✅ Shared module change doesn't break NixOS (re-verify before first Darwin activation)

**Maximum risk:** Shared module change corrupts NixOS or Darwin Nix store. **Mitigation:** Platform conditionals + regression test after shared change.

---

## Files Modified & Created

**Modified (3):**
- `/Users/javels/nix-config/flake.nix` — Add nix-darwin input, darwinConfigurations block
- `/Users/javels/nix-config/modules/shared/nix.nix` — Add platform conditionals
- `/Users/javels/nix-config/home/default.nix` — Add Darwin routing and homeDirectory logic

**Created (9):**
- `/Users/javels/nix-config/hosts/macbook-pro/default.nix`
- `/Users/javels/nix-config/modules/darwin/core.nix`
- `/Users/javels/nix-config/modules/darwin/homebrew.nix`
- `/Users/javels/nix-config/modules/darwin/stylix.nix`
- `/Users/javels/nix-config/home/darwin/default.nix`
- `/Users/javels/nix-config/home/darwin/aerospace.nix`
- `/Users/javels/nix-config/home/darwin/desktop.nix`
- `/Users/javels/nix-config/apps/build-switch-darwin`
- `/Users/javels/nix-config/apps/bootstrap-darwin`

**Total: 12 file changes (3 modified, 9 created)**

---

**Document Status:** Deployment Verification Checklist — Ready for Phase Implementation

**Review Date:** Before first Darwin activation attempt

**Approval Gate:** NixOS regression test passes + all 9 files created + git commits ready
