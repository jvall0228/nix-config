# Critical Edge Cases: Darwin Activation

**Reference:** `docs/checklists/2026-03-04-darwin-activation-checklist.md`

This document drills into the three highest-risk edge cases that could cause data loss, silent corruption, or platform-wide breakage.

---

## Edge Case 1: Shared Module Change Breaks NixOS silently

**Risk Level:** CRITICAL
**Impact:** NixOS Nix store corrupted or gc misconfigured, discovered only after next rebuild
**Probability:** HIGH if `lib.mkIf` conditional has typo

### The Problem

The change to `modules/shared/nix.nix` must use platform conditionals:

```nix
# BAD — applies to all platforms
nix.settings.auto-optimise-store = true;  # BREAKS Darwin store
nix.gc.dates = "weekly";  # BREAKS Darwin (expects launchd interval)

# GOOD — platform-gated
auto-optimise-store = !pkgs.stdenv.isDarwin;  # false on Darwin, true on Linux
nix.gc = lib.mkIf pkgs.stdenv.isLinux { dates = "weekly"; ... };
```

**Why this is dangerous:**
- Both changes are in a *shared* module imported by NixOS and Darwin
- If the conditional has a typo (e.g., `lib.mkIff` instead of `lib.mkIf`), NixOS won't evaluate at all
- If the conditional is correct but `lib` isn't imported, NixOS evaluates but has broken gc config
- If `auto-optimise-store = true` accidentally leaks to Darwin, the *Darwin Nix store becomes corrupted* (inode mismatch)
- The corruption isn't discovered until a subsequent `nix-store --verify` or garbage collection attempts

### Detection Strategies

**Before commit:**
```bash
# Verify the exact syntax
grep -A 2 "lib.mkIf" ~/nix-config/modules/shared/nix.nix
# Must show: lib.mkIf pkgs.stdenv.isLinux {

# Verify lib is in function signature
head -1 ~/nix-config/modules/shared/nix.nix
# Must show: { user, lib, pkgs, ... }:

# Verify both conditionals are there
grep -c "auto-optimise-store = !pkgs.stdenv.isDarwin" ~/nix-config/modules/shared/nix.nix
# Expected: 1

grep -c "lib.mkIf pkgs.stdenv.isLinux" ~/nix-config/modules/shared/nix.nix
# Expected: 1
```

**After modifying, before committing:**
```bash
# NixOS evaluation test (must not error)
nix eval .#nixosConfigurations.thinkpad.config.nix.gc.dates --json
# Expected: "weekly"

nix eval .#nixosConfigurations.thinkpad.config.nix.settings.auto-optimise-store --json
# Expected: true

# Darwin evaluation test (gc should not have dates)
nix eval .#darwinConfigurations.macbook-pro.config.nix.gc --json
# Expected: Should have interval, NOT dates
```

**If NixOS breaks after shared module change:**
```bash
# Check what went wrong in evaluation
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel 2>&1 | head -30

# Likely error patterns:
# - "attribute 'mkIf' missing" → lib not imported
# - "undefined variable 'lib'" → lib not added to signature
# - "is a function, expected an attribute set" → lib.mkIf syntax error

# Examine the exact line
sed -n '1p; 100,110p' ~/nix-config/modules/shared/nix.nix  # line 1 and gc section
```

### Rollback Procedure

**If NixOS evaluation fails after shared module change:**

```bash
# 1. Immediately revert the shared module change
git checkout HEAD~1 -- modules/shared/nix.nix
# or
git diff HEAD~1 modules/shared/nix.nix  # to see what changed

# 2. Test NixOS evaluation again
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel --json > /dev/null
# Should succeed now

# 3. Create a new commit with the fix
# (don't amend the original, so we have clear history)
git add modules/shared/nix.nix
git commit -m "fix: correct lib.mkIf syntax in shared nix module"
```

**If NixOS evaluation succeeded but gc is broken on next rebuild:**

```bash
# Check what gc config is actually set
cat /etc/nix/nix.conf | grep -A 3 "gc"

# If gc.dates is missing (should be there):
# The conditional worked, but maybe interval is corrupted

# Manually verify NixOS state version safety
nix-channel --list
systemctl status nix-gc.timer
systemctl show nix-gc.timer

# To recover: a full rebuild with known-good shared module
git checkout <known-good-commit> -- modules/shared/nix.nix
sudo nixos-rebuild switch --flake ~/nix-config#thinkpad
```

### Prevention Checklist

Before pushing shared module change:

- [ ] Run `nix eval .#nixosConfigurations.thinkpad.config.nix.gc.dates --json` — must return `"weekly"`
- [ ] Run `nix eval .#nixosConfigurations.thinkpad.config.nix.settings.auto-optimise-store --json` — must return `true`
- [ ] Verify Darwin evaluates (may not build on Linux, but shouldn't *error* on eval): `nix eval .#darwinConfigurations.macbook-pro.config.system.build.toplevel --json` — should not error
- [ ] Test on actual NixOS: `nixos-rebuild dry-build --flake ~/nix-config#thinkpad` — must complete
- [ ] Commit shared module change separately from Darwin changes (isolation)
- [ ] Do NOT merge to main until NixOS validation passes

---

## Edge Case 2: Bootstrap Script Fails Partway, Leaves System in Unusable State

**Risk Level:** HIGH
**Impact:** Fresh Mac with partial Nix/Homebrew install, repos cloned, but first activation failed; unclear how to resume
**Probability:** MEDIUM (network timeouts, interactive step failures)

### The Problem

The bootstrap flow is:
1. Xcode CLT (interactive, ~15 min)
2. Nix (auto-run installer)
3. Homebrew (interactive password prompt)
4. Git clone repo
5. First darwin-rebuild activation (30-60 min, downloads packages)

If any step fails, subsequent re-runs of the script must:
- Skip already-completed steps (idempotency)
- Resume from the failed point (not restart from beginning)
- NOT corrupt state if partially-failed setup exists

### Failure Scenarios

**Scenario A: Xcode CLT install never completes**
```bash
# User starts bootstrap
bash ~/Downloads/bootstrap-darwin.sh
# Xcode CLT dialog appears, user never clicks Install
# Script waits forever (blocks on `read -r`)
# User force-quits script with Ctrl+C
```

**Issue:** If user re-runs bootstrap and Xcode CLT is partially installed:
```bash
# The check `xcode-select -p &>/dev/null` might return different things:
# - If clipped mid-install: might fail, triggering reinstall attempt
# - If clipped after headers: might succeed, so script continues to Nix

# Expected behavior: Script should be forgiving
```

**Detection:**
```bash
xcode-select -p 2>&1
# Returns: /path/to/Xcode or error message

# The bootstrap check is:
if ! xcode-select -p &>/dev/null; then
  echo "Installing Xcode CLT..."
else
  echo "Xcode CLT: already installed"
fi
# This is good — idempotent check
```

**Scenario B: Nix installer succeeds, but nix-daemon.sh not found**

```bash
# Determinate Systems installer runs but doesn't create /nix/var/nix/profiles/.../nix-daemon.sh
# Next step tries to source it; file not found
# Script continues (uses `if [ -e ... ]`)
# But `nix` command might not work in subsequent shell commands

if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

# Then immediately:
if ! command -v nix &>/dev/null; then
  echo "Error: Nix not found in PATH after installation."
  echo "Please open a new terminal and re-run this script."
  exit 1
fi
```

**This is handled correctly** — if sourcing fails, the script detects `nix` missing and exits with clear instructions.

**Scenario C: Homebrew install timeout during network step**

```bash
# Homebrew installer is downloading core files
# Network drops or times out
# Script exits (curl fails)
# User re-runs bootstrap
```

**Expected behavior:**
```bash
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL ...)"
  # If curl times out here, script fails
else
  echo "Homebrew: already installed"
fi

# Re-running: the check `command -v brew` will fail (Homebrew not complete)
# Script tries to reinstall Homebrew (may conflict with partial install)
```

**Issue:** Homebrew partial install might leave `/opt/homebrew` in a bad state. Reinstalling from scratch could cause conflicts.

**Mitigation in script:**
```bash
# Current script is safe because:
# 1. If Homebrew install fails, `brew` command won't exist
# 2. Re-running the script will retry Homebrew install
# 3. Homebrew installer is idempotent (can be run multiple times)
# 4. BUT: If user has partial Homebrew (with `brew` available but broken):
#    - Script skips reinstall
#    - subsequent `nix run nix-darwin#darwin-rebuild` will fail at Homebrew cask install
#    - User needs to manually clean up: `brew --version` or uninstall Homebrew
```

**Scenario D: First activation fails at package download (30 min in)**

```bash
# darwin-rebuild switch starts downloading packages
# 30 minutes into the process, network timeout
# nix-darwin process dies
# System is now in a partially-activated state
```

**Packages downloaded so far:**
- `/nix/store/` has partial closure
- Home directory partially configured (some dotfiles symlinked)
- System config partially applied (some Homebrew casks installed)

**Re-running bootstrap:**
```bash
cd ~/nix-config
# User tries:
nix run nix-darwin#darwin-rebuild -- switch --flake ".#macbook-pro"
# or via script:
bash ~/nix-config/apps/build-switch-darwin

# Expected: Downloads resume from where they left off
# Nix cache + store verification ensures no re-download of completed packages
# home-manager detects existing config and applies diff only
```

**This is safe because:**
- Nix is content-addressed (downloaded packages aren't re-fetched)
- home-manager uses `backupFileExtension = "backup"` (renames conflicts, doesn't overwrite)
- darwin-rebuild is idempotent (can retry activation)

### Detection & Recovery

**If bootstrap stalls:**
```bash
# Check which step is active
ps aux | grep -E "curl|xcode-select|brew|nix" | grep -v grep
# If curl is hung: kill and re-run bootstrap

# If Nix installer hung:
# - Ctrl+C, open new terminal, re-run bootstrap
# - Script will detect `nix` already exists (or not) and skip/retry

# If Homebrew hung:
# - Ctrl+C, run `brew doctor` to check state
# - If broken: uninstall Homebrew manually, re-run bootstrap
# - If OK: bootstrap will detect and skip

# If first activation hung:
# - Ctrl+C
# - Check what's partially installed: `nix store verify` or `ls /nix/store`
# - Re-run: `bash ~/nix-config/apps/build-switch-darwin`
# - Or: `cd ~/nix-config && nix run nix-darwin#darwin-rebuild -- switch --flake ".#macbook-pro"`
```

**If Homebrew is in a bad state:**
```bash
# Test Homebrew health
brew doctor

# If broken, uninstall and re-run bootstrap
# (Homebrew installer handles reinstalls)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"

# Then re-run bootstrap
bash ~/nix-config/apps/bootstrap-darwin
```

**If first activation is stuck:**
```bash
# Check what darwin-rebuild is doing
ps aux | grep darwin-rebuild
# Look for nix or download processes

# If nothing is happening, kill the process:
pkill darwin-rebuild

# Check nix-store state:
nix store verify --repair

# Retry activation:
darwin-rebuild switch --flake ~/nix-config#macbook-pro
```

### Idempotency Validation Checklist

Before shipping `bootstrap-darwin`, test each step:

**Test 1: Script is safe to re-run when all tools exist**
```bash
# Scenario: Run bootstrap on a Mac where Xcode CLT, Nix, Homebrew already exist
# and repo is already cloned

bash ~/nix-config/apps/bootstrap-darwin
# Expected output:
# Xcode CLT: already installed
# Nix: already installed
# Homebrew: already installed
# Repo: already exists at $HOME/nix-config
# [Runs first activation again, which is safe]
```

**Test 2: Script handles missing intermediate tools**
```bash
# Scenario: Nix is installed, but Homebrew isn't
# (or any other combination)

# Manually uninstall Homebrew:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"

# Run bootstrap:
bash ~/nix-config/apps/bootstrap-darwin
# Expected: Skips Xcode CLT and Nix, installs Homebrew, continues
```

**Test 3: Script resumes after interactive step failure**
```bash
# Scenario: Xcode CLT install asked for interaction, user didn't respond

# Run bootstrap with timeout (simulate user giving up):
timeout 5 bash ~/nix-config/apps/bootstrap-darwin || true

# Check state:
xcode-select -p
# If succeeded before timeout: /Applications/Xcode.app/...
# If timed out during: error

# Re-run bootstrap:
bash ~/nix-config/apps/bootstrap-darwin
# Expected: Script detects state and resumes appropriately
```

---

## Edge Case 3: Homebrew State Management & Cask Cleanup Edge Case

**Risk Level:** MEDIUM
**Impact:** Accidentally uninstall or miss-configure user-installed apps
**Probability:** MEDIUM (user manually installs cask outside of nix config)

### The Problem

The Homebrew config includes:

```nix
homebrew = {
  enable = true;
  onActivation = {
    autoUpdate = true;
    upgrade = true;
    cleanup = "uninstall";  # ← KEY SETTING
  };
  casks = [
    "firefox"
    "1password"
    "discord"
    ...
  ];
};
```

**What `cleanup = "uninstall"` does:**
- After activation, Homebrew compares installed casks with declared casks in config
- Any cask NOT in the config list is uninstalled
- `cleanup = "uninstall"` uninstalls the app, but leaves data in `~/Library/Application Support/` (safe)
- `cleanup = "zap"` would be destructive (removes all cask data)

**Danger zone:**
User manually installs a cask outside of Nix:
```bash
# User runs (not via Nix):
brew install spotify

# Then runs darwin-rebuild:
bash apps/build-switch-darwin

# If "spotify" is not in modules/darwin/homebrew.nix casks list:
# It gets uninstalled!
# (But Spotify data remains in ~/Library/Application Support/Spotify/)
```

### Detection Strategy

**Before first activation:**

1. **Audit the cask list** — ensure all intended apps are in `modules/darwin/homebrew.nix`:
   ```bash
   grep -A 20 "casks = \[" ~/nix-config/modules/darwin/homebrew.nix | grep '"'
   # Should list: firefox, 1password, discord, slack, spotify, obsidian, vscode, telegram, raycast
   ```

2. **Ensure the list is maintainable** — if future user installs something manually, they must:
   - Add it to `modules/darwin/homebrew.nix`
   - Commit and re-run `darwin-rebuild`
   - OR accept that the next rebuild will uninstall it

3. **Document the expectation** — this should be in CLAUDE.md:
   ```markdown
   ## Homebrew Cask Management

   Nix-darwin manages Homebrew casks declaratively via modules/darwin/homebrew.nix.

   If you install a cask manually via `brew install <name>`, remember to:
   1. Add it to modules/darwin/homebrew.nix
   2. Run `bash apps/build-switch-darwin`

   If you forget, the next rebuild will uninstall manually-installed casks
   (but data is preserved in ~/Library/Application Support/).
   To restore: `brew install <name>` or add to config and re-build.
   ```

### Mitigation: Pre-Activation Cask Audit

**Before first darwin-rebuild switch:**

```bash
# List what's currently installed on the Mac
brew list --cask

# Check what modules/darwin/homebrew.nix declares
grep -A 20 "casks = \[" ~/nix-config/modules/darwin/homebrew.nix

# Compare — ensure anything important is in the config
# If user has manually installed apps, add them to the config
```

### Failure Scenario: User Loses App After Rebuild

**Scenario:** User has manually installed "Figma":
```bash
brew install figma
# User forgot this is not in the Nix config

# Later, runs:
bash apps/build-switch-darwin

# Figma gets uninstalled (cleanup = "uninstall")
# User notices Figma is gone from Applications
```

**Recovery:**

1. **Figma data is NOT lost** (it's in ~/Library/Application Support/):
   ```bash
   ls -la ~/Library/Application\ Support/ | grep -i figma
   # Should show Figma data directory intact
   ```

2. **Reinstall Figma:**
   ```bash
   # Option A: Via Homebrew
   brew install figma

   # Option B: Add to nix config (persistent)
   # Edit modules/darwin/homebrew.nix, add "figma" to casks list
   # Run: bash apps/build-switch-darwin
   ```

3. **Prevent future loss:**
   - Add "figma" to `modules/darwin/homebrew.nix`
   - Commit the change
   - Figma will stay installed across future rebuilds

### Homebrew State Verification

**Post-activation check:**

```bash
# List all installed casks
brew list --cask
# Expected: firefox, 1password, discord, slack, spotify, obsidian, vscode, telegram, raycast

# Cross-reference with config
for cask in firefox 1password discord slack spotify obsidian vscode telegram raycast; do
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
✓ vscode installed
✓ telegram installed
✓ raycast installed
```

If any are missing, either:
1. Homebrew install failed (check network, try again)
2. Cask name is wrong in config (check `brew search <name>`)
3. macOS version incompatible with cask

### Edge Case: One Cask Fails to Install

**Scenario:** One cask (e.g., "obsidian") fails to download during first activation:

```bash
# darwin-rebuild switch starts, downloads packages
# At Homebrew cask install step:
# obsidian.dmg download times out
# Obsidian install fails; others succeed

# darwin-rebuild continues (doesn't fail)
# User now has: firefox, 1password, discord, etc. installed
# But obsidian is missing
```

**Recovery:**

```bash
# Option 1: Retry the full build (safest)
bash apps/build-switch-darwin
# Nix skips already-installed packages, Homebrew retries obsidian

# Option 2: Manually install the missing cask
brew install obsidian

# Option 3: Check what went wrong
brew install obsidian --verbose
# Review error message; may be network or macOS version issue
```

**Why this is safe:**
- `homebrew.onActivation.cleanup = "uninstall"` only triggers uninstall of casks NOT in the config
- A cask that failed to install is not in Homebrew's "installed" list
- Retrying darwin-rebuild will attempt the install again
- No data loss (cask was never installed in the first place)

### Prevention Checklist

Before first activation:

- [ ] Review `modules/darwin/homebrew.nix` cask list — is it complete?
- [ ] For each cask, verify it's available for aarch64 (Apple Silicon):
  ```bash
  nix run nixpkgs#curl -- -s "https://api.github.com/repos/Homebrew/homebrew-casks/contents/Casks/f/firefox.rb" | head -1
  # (or: brew search firefox)
  ```
- [ ] Verify `cleanup = "uninstall"` (not `"zap"`) — preserves data
- [ ] Document the Homebrew cask policy in CLAUDE.md
- [ ] Plan for potential cask failures — have list of alternatives or manual install steps
- [ ] Test one full activation cycle where one cask is temporarily commented out, verify it gets uninstalled

---

## Summary: Top 3 Mitigation Strategies

| Edge Case | Mitigation | Verification |
|-----------|-----------|---------------|
| **Shared module breaks NixOS** | Platform conditionals (`lib.mkIf`) + NixOS evaluation test before commit | `nix eval .#nixosConfigurations.thinkpad.config.nix.gc.dates` returns `"weekly"` |
| **Bootstrap fails partway** | Idempotent checks + resume-from-failure support + clear error messages | Test bootstrap 3x: fresh, with partial installs, after intentional failure |
| **Homebrew state loss** | Document cask policy + audit pre-activation + validate post-activation | `brew list --cask` matches config after first build; retry mechanism works |

---

**Document Status:** Critical Edge Cases Reference — Use during implementation and testing

**Review Dates:**
- Before first Darwin activation
- During post-activation verification (reference edge case 3)
- During NixOS regression testing (reference edge case 1)
