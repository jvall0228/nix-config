# Darwin Activation: Verification Queries & Data Invariants

**Reference:** `docs/checklists/2026-03-04-darwin-activation-checklist.md`

This document provides executable bash/nix queries to verify data invariants before, during, and after Darwin activation. Use these as regression tests and as a post-mortem checklist if anything goes wrong.

---

## Baseline Queries (Pre-Activation)

Run these on NixOS to establish a baseline for comparison.

### Query 1: NixOS nix.gc Configuration

**Purpose:** Baseline to verify shared module conditionals don't break Linux.

```bash
# On ThinkPad (NixOS)
nix eval .#nixosConfigurations.thinkpad.config.nix.gc --json | jq '.'
```

**Expected output:**
```json
{
  "automatic": true,
  "dates": "weekly",
  "options": "--delete-older-than 30d"
}
```

**Save this baseline:**
```bash
nix eval .#nixosConfigurations.thinkpad.config.nix.gc --json > /tmp/nixos-gc-baseline.json
cat /tmp/nixos-gc-baseline.json
# Expected: contains "dates": "weekly"
```

### Query 2: NixOS auto-optimise-store Setting

**Purpose:** Verify it's true on Linux, not false.

```bash
nix eval .#nixosConfigurations.thinkpad.config.nix.settings.auto-optimise-store --json
```

**Expected output:**
```json
true
```

**Save baseline:**
```bash
nix eval .#nixosConfigurations.thinkpad.config.nix.settings.auto-optimise-store --json > /tmp/nixos-optimize-baseline.json
# Expected content: true
```

### Query 3: Home-Manager Shell Aliases (Cross-Platform Baseline)

**Purpose:** Ensure shell aliases will be available on both Linux and Darwin.

```bash
# On NixOS, check what aliases are defined
nix eval '.#nixosConfigurations.thinkpad.config.home-manager.users.javels.home.shellAliases' --json | jq 'keys | sort' | head -10
```

**Expected output (must use `home.shellAliases`, NOT `programs.bash.shellAliases`):**
```json
[
  "ll",
  "la",
  "ls",
  ...
]
```

**Critical check:**
```bash
# MUST pass: alias definitions are in home.shellAliases (platform-neutral)
nix eval '.#nixosConfigurations.thinkpad.config.home-manager.users.javels.home.shellAliases' --json | grep -q 'll' && echo "PASS: Aliases in home.shellAliases" || echo "FAIL: Aliases missing"
```

**If this fails:** `home/common/shell.nix` uses `programs.bash.shellAliases` instead. Must extract to `home.shellAliases` before Darwin activation.

### Query 4: Module File Existence Check

**Purpose:** Ensure no new files will conflict with existing structure.

```bash
# These should NOT exist yet
[ -d ~/nix-config/modules/darwin ] && echo "FAIL: modules/darwin already exists" || echo "PASS: modules/darwin safe to create"
[ -d ~/nix-config/home/darwin ] && echo "FAIL: home/darwin already exists" || echo "PASS: home/darwin safe to create"
[ -f ~/nix-config/apps/build-switch-darwin ] && echo "FAIL: build-switch-darwin exists" || echo "PASS: build-switch-darwin safe to create"
[ -f ~/nix-config/apps/bootstrap-darwin ] && echo "FAIL: bootstrap-darwin exists" || echo "PASS: bootstrap-darwin safe to create"
```

**Expected output:**
```
PASS: modules/darwin safe to create
PASS: home/darwin safe to create
PASS: build-switch-darwin safe to create
PASS: bootstrap-darwin safe to create
```

---

## Post-Shared-Module-Change Verification

After modifying `modules/shared/nix.nix`, run these before committing.

### Query 5: Verify lib.mkIf Syntax in Shared Module

**Purpose:** Catch typos in platform conditionals.

```bash
# Check exact syntax
grep "lib.mkIf pkgs.stdenv.isLinux" ~/nix-config/modules/shared/nix.nix && echo "PASS: lib.mkIf found" || echo "FAIL: lib.mkIf not found"

# Check it's correctly closing the block
grep -A 5 "lib.mkIf pkgs.stdenv.isLinux" ~/nix-config/modules/shared/nix.nix | grep -q "^  };" && echo "PASS: block closing found" || echo "FAIL: block not closed correctly"
```

**Expected output:**
```
PASS: lib.mkIf found
PASS: block closing found
```

### Query 6: Verify lib and pkgs in Function Signature

**Purpose:** Ensure shared module can access lib and pkgs.

```bash
# Check function signature
head -1 ~/nix-config/modules/shared/nix.nix | grep -q "lib, pkgs" && echo "PASS: lib and pkgs in signature" || echo "FAIL: Missing lib or pkgs"
```

**Expected output:**
```
PASS: lib and pkgs in signature
```

**Exact required line:**
```
{ user, lib, pkgs, ... }:
```

### Query 7: NixOS Evaluation After Shared Module Change

**Purpose:** Verify NixOS still evaluates correctly.

```bash
# Full evaluation (this is the gold standard test)
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel --json > /dev/null 2>&1 && echo "PASS: NixOS evaluates" || echo "FAIL: NixOS evaluation error"

# If evaluation fails, get the error:
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel --json 2>&1 | head -30
```

**Expected output (on success):**
```
PASS: NixOS evaluates
```

**On failure, common patterns to look for:**
```
error: undefined variable 'lib'
error: attribute 'mkIf' missing
error: expected an attribute set, got a function
```

Any of these indicates syntax error in shared module.

### Query 8: NixOS gc Configuration After Change

**Purpose:** Verify the conditional evaluates correctly for Linux.

```bash
# After shared module change, this must still be "weekly"
nix eval .#nixosConfigurations.thinkpad.config.nix.gc.dates --json
```

**Expected output:**
```json
"weekly"
```

**Compare with baseline:**
```bash
nix eval .#nixosConfigurations.thinkpad.config.nix.gc.dates --json > /tmp/nixos-gc-after.json
diff /tmp/nixos-gc-baseline.json /tmp/nixos-gc-after.json
# Expected: identical (no diff output)
```

### Query 9: NixOS auto-optimise-store After Change

**Purpose:** Verify auto-optimise-store is still true on Linux.

```bash
nix eval .#nixosConfigurations.thinkpad.config.nix.settings.auto-optimise-store --json
```

**Expected output:**
```json
true
```

**Verify no change from baseline:**
```bash
nix eval .#nixosConfigurations.thinkpad.config.nix.settings.auto-optimise-store --json > /tmp/nixos-optimize-after.json
diff /tmp/nixos-optimize-baseline.json /tmp/nixos-optimize-after.json
# Expected: identical
```

### Query 10: Dry-Build NixOS System

**Purpose:** Full build check (most thorough, takes time).

```bash
# This tests the entire NixOS configuration
nixos-rebuild dry-build --flake ~/nix-config#thinkpad 2>&1 | tee /tmp/nixos-drybuild.log

# Check result
tail -1 /tmp/nixos-drybuild.log | grep -q "these derivations" && echo "PASS: NixOS dry-build succeeded" || echo "FAIL: See log"
```

**Expected output:**
```
PASS: NixOS dry-build succeeded
these derivations will be built:
  /nix/store/...-nixos-system-thinkpad-25.05.drv
```

---

## Post-Module-Creation Verification

After creating all Darwin modules, before first activation.

### Query 11: Darwin Flake Evaluation

**Purpose:** Verify all Darwin modules can be loaded without errors.

```bash
# Can evaluate on any platform (won't build on Linux, but shouldn't error)
nix eval .#darwinConfigurations.macbook-pro.config.system.build.toplevel --json > /dev/null 2>&1 && echo "PASS: Darwin evaluates" || echo "FAIL: Darwin evaluation error"

# On failure, get error:
nix eval .#darwinConfigurations.macbook-pro.config.system.build.toplevel --json 2>&1 | head -30
```

**Expected output:**
```
PASS: Darwin evaluates
```

### Query 12: Darwin Hostname Configuration

**Purpose:** Verify host config is correct.

```bash
nix eval '.#darwinConfigurations.macbook-pro.config.networking.hostName' --json
nix eval '.#darwinConfigurations.macbook-pro.config.networking.localHostName' --json
nix eval '.#darwinConfigurations.macbook-pro.config.networking.computerName' --json
```

**Expected output:**
```json
"macbook-pro"
"macbook-pro"
"macbook-pro"
```

### Query 13: Darwin gc Configuration

**Purpose:** Verify Darwin uses launchd interval, not systemd dates.

```bash
# Darwin should have interval (launchd format)
nix eval '.#darwinConfigurations.macbook-pro.config.nix.gc' --json | jq '.interval'
```

**Expected output:**
```json
[
  {
    "Hour": 4,
    "Minute": 0
  }
]
```

**Verify it does NOT have dates:**
```bash
nix eval '.#darwinConfigurations.macbook-pro.config.nix.gc' --json | jq '.dates' 2>&1 | grep -q "null" && echo "PASS: No dates field" || echo "FAIL: dates field present"
```

**Expected output:**
```
PASS: No dates field
```

### Query 14: Darwin auto-optimise-store Setting

**Purpose:** Verify it's false on Darwin (not true).

```bash
nix eval .#darwinConfigurations.macbook-pro.config.nix.settings.auto-optimise-store --json
```

**Expected output:**
```json
false
```

### Query 15: Darwin Homebrew Configuration

**Purpose:** Verify cask list is present.

```bash
nix eval '.#darwinConfigurations.macbook-pro.config.homebrew.enable' --json
nix eval '.#darwinConfigurations.macbook-pro.config.homebrew.casks' --json | jq 'length'
```

**Expected output:**
```json
true
9
```

**List all casks:**
```bash
nix eval '.#darwinConfigurations.macbook-pro.config.homebrew.casks' --json | jq '.[]' | sort
```

**Expected output:**
```json
"1password"
"discord"
"firefox"
"obsidian"
"raycast"
"slack"
"spotify"
"telegram"
"visual-studio-code"
```

### Query 16: Home-Manager Platform Routing

**Purpose:** Verify home/default.nix conditionals work.

```bash
# On NixOS, homeDirectory should be /home/javels
nix eval '.#nixosConfigurations.thinkpad.config.home-manager.users.javels.home.homeDirectory' --json
```

**Expected output (NixOS):**
```json
"/home/javels"
```

**Verify Darwin path (can't test fully on Linux, but check evaluation):**
```bash
# This should evaluate without error (won't know the value on Linux, but syntax is correct)
nix eval '.#darwinConfigurations.macbook-pro.config.home-manager.users.javels.home.homeDirectory' --json 2>&1 | head -5
```

**Expected output (Darwin, when later tested on macOS):**
```json
"/Users/javels"
```

### Query 17: Aerospace Configuration

**Purpose:** Verify keybindings are loaded.

```bash
# Check that Aerospace is enabled
nix eval '.#darwinConfigurations.macbook-pro.config.home-manager.users.javels.programs.aerospace.enable' --json
```

**Expected output:**
```json
true
```

**Check a specific keybinding exists:**
```bash
nix eval '.#darwinConfigurations.macbook-pro.config.home-manager.users.javels.programs.aerospace.settings.mode.main.binding' --json | jq '."alt-h"'
```

**Expected output:**
```json
"focus left"
```

### Query 18: Stylix Configuration

**Purpose:** Verify Stylix targets are explicitly enabled.

```bash
nix eval '.#darwinConfigurations.macbook-pro.config.stylix.autoEnable' --json
```

**Expected output (must be false to prevent errors on nonexistent targets):**
```json
false
```

**Verify explicit targets:**
```bash
nix eval '.#darwinConfigurations.macbook-pro.config.stylix.targets' --json | jq 'keys'
```

**Expected output (at minimum):**
```json
[
  "bat",
  "btop",
  "kitty"
]
```

---

## Post-Activation Verification Queries

After `darwin-rebuild switch` succeeds on macOS.

### Query 19: System Defaults Applied

**Purpose:** Verify system.defaults made it to plist files.

```bash
# Dock autohide
defaults read com.apple.dock autohide
# Expected: 1

# Dark mode
defaults read -g AppleInterfaceStyle
# Expected: Dark

# Finder show extensions
defaults read com.apple.finder AppleShowAllExtensions
# Expected: 1

# Key repeat rate
defaults read -g KeyRepeat
# Expected: 2
```

**Bundle all checks:**
```bash
cat << 'EOF' > /tmp/verify-defaults.sh
#!/bin/bash
checks=(
  "com.apple.dock autohide:1"
  "-g AppleInterfaceStyle:Dark"
  "com.apple.finder AppleShowAllExtensions:1"
  "-g KeyRepeat:2"
)

for check in "${checks[@]}"; do
  domain="${check%%:*}"
  key="${domain##* }"
  domain="${domain% *}"
  expected="${check##*:}"

  actual=$(defaults read $domain $key 2>/dev/null || echo "NOTFOUND")
  if [ "$actual" = "$expected" ]; then
    echo "✓ $key = $expected"
  else
    echo "✗ $key: expected '$expected', got '$actual'"
  fi
done
EOF

bash /tmp/verify-defaults.sh
```

### Query 20: Homebrew Cask Installation Status

**Purpose:** Verify all casks were installed.

```bash
# Check if all expected casks are installed
expected_casks=("firefox" "1password" "discord" "slack" "spotify" "obsidian" "visual-studio-code" "telegram" "raycast")

for cask in "${expected_casks[@]}"; do
  if brew list --cask | grep -q "^$cask\$"; then
    echo "✓ $cask installed"
  else
    echo "✗ $cask MISSING"
  fi
done
```

**Expected output:**
```
✓ firefox installed
✓ 1password installed
✓ discord installed
✓ slack installed
✓ spotify installed
✓ obsidian installed
✓ visual-studio-code installed
✓ telegram installed
✓ raycast installed
```

**Count comparison:**
```bash
# These should be equal (or all casks accounted for)
echo "Expected casks: 9"
echo "Installed casks: $(brew list --cask | wc -l)"
```

### Query 21: Home-Manager Generation Active

**Purpose:** Verify home-manager config was activated.

```bash
# Show active home-manager generation
home-manager generations | head -3
```

**Expected output (shows at least one generation):**
```
2026-03-04 10:30 -> /nix/store/...-home-manager-generation
```

**Verify key files are symlinked:**
```bash
# Check home-manager managed files
ls -la ~/.config/ | grep -E "kitty|nvim|tmux"
# Expected: shows symlinks to /nix/store/...

# Check if they're indeed symlinks
[ -L ~/.config/kitty ] && echo "✓ kitty is symlinked" || echo "✗ kitty not symlinked"
```

### Query 22: Stylix Theme Applied

**Purpose:** Verify Tokyo Night Dark theme is in place.

```bash
# Check kitty colors
cat ~/.config/kitty/colors.conf | head -5
# Should show color definitions

# Verify bat theme
bat --list-themes | grep -i tokyo
# Expected: shows "Tokyo Night Dark" or similar

# Check btop theme
grep "^color_theme" ~/.config/btop/btop.conf
# Expected: contains theme name
```

### Query 23: Nix Garbage Collection Scheduled

**Purpose:** Verify nix.gc launchd agent is active.

```bash
# On macOS, check launchd:
launchctl list | grep nix
# Expected: shows nix-gc launch agent

# Check the plist configuration:
launchctl list org.nix-community.home.nix-gc 2>&1 | head -5
# Expected: shows launchd config or "unknown response" (which is OK)

# Alternative: check if launchd job will fire at 04:00
cat ~/Library/LaunchAgents/org.nixos.nix-gc.plist 2>/dev/null | grep -A 2 "Hour" | head -5
# Expected: shows Hour = 4
```

### Query 24: Aerospace Tiling WM Active

**Purpose:** Verify Aerospace daemon is running.

```bash
# Check if process is running
ps aux | grep -i aerospace | grep -v grep && echo "✓ Aerospace running" || echo "✗ Aerospace NOT running"

# Check config file exists
[ -f ~/.config/aerospace/aerospace.toml ] && echo "✓ Config file exists" || echo "✗ Config file missing"

# Verify keybindings are in config
grep "alt-h" ~/.config/aerospace/aerospace.toml && echo "✓ Keybindings found" || echo "✗ Keybindings missing"
```

### Query 25: Shell Aliases Available

**Purpose:** Verify zsh has inherited aliases from home/common/shell.nix.

```bash
# Test common aliases
alias | grep -E "^ll|^la" | head -3
# Expected: shows ll and la aliases

# Test one explicitly
ll /tmp
# Expected: long format listing of /tmp

# Verify alias sources from home-manager
grep -r "alias ll" ~/.config/ 2>/dev/null | head -1
# Expected: shows zsh config sourced from home-manager
```

### Query 26: Touch ID for sudo Works

**Purpose:** Verify PAM configuration allows Touch ID.

```bash
# Test Touch ID authentication
sudo -v
# You should be prompted for Touch ID biometric, not password

# Check PAM config was written
cat /etc/pam.d/sudo_local 2>/dev/null | grep pam_reattach
# Expected: shows pam_reattach.so entry

# In tmux, verify pam-reattach is working
tmux new-session -d -s test
tmux send-keys -t test "sudo -v" Enter
# Touch ID should work (may need retry)
```

### Query 27: Nix Daemon Configuration

**Purpose:** Verify nix.conf has correct settings from shared module.

```bash
# Check auto-optimise-store is false (Darwin safety)
cat /etc/nix/nix.conf | grep auto-optimise-store
# Expected: auto-optimise-store = false

# Check substituters are configured
cat /etc/nix/nix.conf | grep substituters
# Expected: lists nixpkgs and community caches

# Verify experimental-features
cat /etc/nix/nix.conf | grep experimental-features
# Expected: includes "nix-command" and "flakes"
```

---

## Regression Testing: NixOS Unaffected

After Darwin activation succeeds, run these on NixOS to ensure nothing broke.

### Query 28: NixOS Still Builds

**Purpose:** Regression test for shared module changes.

```bash
# On ThinkPad (NixOS)
nixos-rebuild dry-build --flake ~/nix-config#thinkpad 2>&1 | tail -5
```

**Expected output:**
```
these derivations will be built:
  /nix/store/...-nixos-system-thinkpad-25.05.drv
```

### Query 29: NixOS nix.gc Still Scheduled

**Purpose:** Verify systemd timer is still active.

```bash
# On NixOS
sudo systemctl status nix-gc.timer
# Expected: enabled and active

# Check next scheduled run
systemctl list-timers nix-gc.timer
# Expected: shows next run time
```

### Query 30: NixOS auto-optimise-store Still Enabled

**Purpose:** Verify store optimization didn't change.

```bash
# On NixOS
sudo cat /etc/nix/nix.conf | grep auto-optimise-store
# Expected: auto-optimise-store = true (NOT false)

# Verify it's still true in evaluated config
nix eval .#nixosConfigurations.thinkpad.config.nix.settings.auto-optimise-store --json
# Expected: true
```

### Query 31: NixOS Home-Manager Still Works

**Purpose:** Verify home-manager can still activate on Linux.

```bash
# On NixOS, test home-manager
home-manager switch -b backup --flake ~/nix-config#thinkpad 2>&1 | tail -5
# Expected: completes without errors

# Check home-manager generation
home-manager generations | head -1
# Expected: shows active generation
```

### Query 32: NixOS Shell Aliases Still Available

**Purpose:** Verify bash aliases still work on Linux.

```bash
# On NixOS
bash -c "alias | grep -c 'll'"
# Expected: 1 (alias exists)

# Test an alias
ll /tmp
# Expected: long format listing
```

---

## Emergency Queries (If Something Went Wrong)

Use these to diagnose problems after activation.

### Query E1: Check Latest Build Error

**Purpose:** Diagnose what went wrong in last build.

```bash
# Get the last darwin-rebuild error
darwin-rebuild switch --flake ~/nix-config#macbook-pro 2>&1 | tail -50 | head -30
# or from log file
cat ~/Library/Logs/nix-darwin.log | tail -50
```

**Look for:**
- "attribute 'X' missing" — config error
- "cannot find" — missing file
- "network error" — download failed
- "permission denied" — install permission issue

### Query E2: Check Nix Store Health

**Purpose:** Verify Nix store isn't corrupted.

```bash
# Verify store
nix store verify --repair
# This takes time, reports any issues
```

### Query E3: Check Homebrew Installation Status

**Purpose:** See what's partially installed.

```bash
# List all casks
brew list --cask

# Check for unfinished installs
brew doctor

# Check cache status
brew cache
```

### Query E4: Check Home-Manager Backup Files

**Purpose:** Verify home-manager preserved existing configs.

```bash
# Look for backup files (home-manager creates these when overwriting)
find ~/.config -name "*.backup" | head -10
# These are the original files before home-manager activation
```

### Query E5: Verify Flake Inputs Are Sane

**Purpose:** Ensure flake.lock isn't corrupted.

```bash
# Check flake lock is valid
nix flake check 2>&1 | head -20

# Show flake lock summary
nix flake metadata | head -10
```

---

## Quick Verification Script

**Copy and run this after activation:**

```bash
#!/bin/bash
set -euo pipefail

echo "=== Darwin Activation Verification ==="
echo ""

# System defaults
echo "System Defaults:"
defaults read com.apple.dock autohide && echo "  ✓ Dock autohide" || echo "  ✗ Dock autohide FAILED"
defaults read -g AppleInterfaceStyle > /dev/null && echo "  ✓ Dark mode" || echo "  ✗ Dark mode FAILED"
defaults read -g KeyRepeat > /dev/null && echo "  ✓ Key repeat" || echo "  ✗ Key repeat FAILED"
echo ""

# Homebrew
echo "Homebrew Casks:"
for cask in firefox 1password discord slack spotify obsidian visual-studio-code telegram raycast; do
  if brew list --cask | grep -q "^$cask\$"; then
    echo "  ✓ $cask"
  else
    echo "  ✗ $cask MISSING"
  fi
done
echo ""

# Home-manager
echo "Home-Manager:"
[ -L ~/.config/kitty ] && echo "  ✓ Kitty configured" || echo "  ✗ Kitty NOT configured"
which nvim > /dev/null && echo "  ✓ Neovim available" || echo "  ✗ Neovim missing"
which tmux > /dev/null && echo "  ✓ Tmux available" || echo "  ✗ Tmux missing"
echo ""

# Aerospace
echo "Aerospace:"
ps aux | grep -i aerospace | grep -v grep > /dev/null && echo "  ✓ Running" || echo "  ✗ NOT running"
[ -f ~/.config/aerospace/aerospace.toml ] && echo "  ✓ Config exists" || echo "  ✗ Config missing"
echo ""

# Nix
echo "Nix Configuration:"
grep "auto-optimise-store = false" /etc/nix/nix.conf > /dev/null && echo "  ✓ Store safety (auto-optimise-store = false)" || echo "  ✗ Store safety NOT set"
grep "experimental-features" /etc/nix/nix.conf > /dev/null && echo "  ✓ Flakes enabled" || echo "  ✗ Flakes NOT enabled"
echo ""

echo "=== Verification Complete ==="
```

**Save as `/tmp/verify-darwin.sh` and run:**
```bash
bash /tmp/verify-darwin.sh
```

---

**Document Status:** Executable Verification Queries — Use for testing, regression, and emergency diagnosis

**Review:** Before each activation phase; save baseline outputs for comparison
