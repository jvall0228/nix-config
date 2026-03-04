# Deployment Checklists & Verification Guides

This directory contains executable checklists, edge case analyses, and verification queries for high-risk deployments in this nix-config repository.

## Documents

### 1. **2026-03-04-darwin-activation-checklist.md** (Primary)

**The main activation and rollback checklist for macOS Darwin configuration.**

**Use this when:**
- Preparing to add nix-darwin support (Phase 1-5 of the plan)
- Activating a new Darwin configuration on macOS
- Debugging a failed activation
- Rolling back a broken deployment

**Sections:**
- Pre-activation verification (NixOS regression testing)
- Phase-by-phase implementation checklist
- First-activation bootstrap flow and edge cases
- Rollback strategy for failed deployments
- Post-activation verification (5 minutes, 24 hours)
- Regression testing to ensure NixOS unaffected
- Emergency procedures for common failures
- Critical path summary (10-point checklist)

**Key gates:**
- NixOS must build after shared module changes ✓
- All 9 Darwin modules created ✓
- Bootstrap script is idempotent ✓
- First activation uses `nix run nix-darwin#darwin-rebuild` ✓

---

### 2. **2026-03-04-darwin-critical-edge-cases.md** (Deep Dives)

**Focused analysis of the three highest-risk edge cases that could cause data loss or platform-wide breakage.**

**Use this when:**
- Implementing Phase 1 (shared module change) — read Edge Case 1
- Preparing for fresh Mac bootstrap — read Edge Case 2
- Configuring Homebrew cask management — read Edge Case 3
- Troubleshooting a specific failure mode

**Covered edge cases:**

1. **Shared Module Platform Conditionals Break NixOS**
   - `lib.mkIf` typo, `auto-optimise-store = true` leaks to Darwin
   - How to detect (eval tests), how to recover (rollback)
   - Prevention: isolation, regression testing

2. **Bootstrap Script Fails Partway, System in Partial State**
   - Xcode CLT hangs, Nix install times out, Homebrew download fails, 30-min activation timeout
   - Idempotency validation (3 test scenarios)
   - Recovery: skip installed tools, resume from failure

3. **Homebrew Cask State & Cleanup Semantics**
   - `cleanup = "uninstall"` removes casks not in config (data preserved)
   - User manually installs cask, loses it on rebuild
   - Mitigation: pre-activation audit, document policy

**Each case includes:**
- Exact failure scenarios with shell commands
- Detection strategies
- Recovery procedures
- Prevention checklists
- Idempotency validation tests

---

### 3. **2026-03-04-darwin-verification-queries.md** (Executable)

**Complete set of bash/nix queries to verify data invariants at each deployment stage.**

**Use this to:**
- Establish pre-activation baselines (save outputs for comparison)
- Validate changes after each phase
- Verify post-activation state (5 min, 24 hour checks)
- Diagnose problems (emergency queries)
- Run regression tests on NixOS

**Organized by phase:**

| Phase | Queries | Purpose |
|-------|---------|---------|
| **Baseline** (5) | NixOS gc, auto-optimise-store, shell aliases, module files | Pre-activation snapshot |
| **Post-Shared-Module** (6) | lib.mkIf syntax, function sig, NixOS eval, gc/optimize, dry-build | Verify shared module safety |
| **Post-Module-Creation** (7) | Darwin eval, hostnames, gc interval, homebrew, home-manager routing | Verify all modules load |
| **Post-Activation** (9) | System defaults, casks, home-manager gen, stylix, gc, Aerospace, aliases, Touch ID, nix.conf | Verify activation success |
| **Regression** (5) | NixOS build, gc timer, auto-optimize, home-manager, aliases | Ensure NixOS unaffected |
| **Emergency** (5) | Last error, store health, Homebrew status, backups, flake lock | Diagnosis for failures |

**Includes:**
- Expected output for each query
- Baseline comparison scripts
- Bundle check scripts for rapid verification
- One-liner post-activation verification script

---

## Quick Reference: Which Document to Use?

```
Preparing the plan?
  → darwin-activation-checklist.md (Phases 1-5)

Worried about broken NixOS?
  → darwin-critical-edge-cases.md (Edge Case 1)

Concerned about bootstrap failures?
  → darwin-critical-edge-cases.md (Edge Case 2)
  → darwin-activation-checklist.md (Bootstrap Idempotency)

Managing Homebrew state?
  → darwin-critical-edge-cases.md (Edge Case 3)
  → darwin-verification-queries.md (Query 20)

Need to verify things are working?
  → darwin-verification-queries.md (Post-Activation section)

Deployment failed?
  → darwin-critical-edge-cases.md (see applicable edge case)
  → darwin-verification-queries.md (Emergency Queries)
  → darwin-activation-checklist.md (Emergency Procedures)

Running regression tests?
  → darwin-verification-queries.md (Regression Testing section)
```

---

## Deployment Flow & Document Alignment

```
PRE-IMPLEMENTATION
├─ Read: darwin-activation-checklist.md (full overview)
├─ Read: darwin-critical-edge-cases.md (understand risks)
└─ Read: darwin-verification-queries.md (baseline section)

PHASE 1: SHARED MODULE FIX
├─ Follow: darwin-activation-checklist.md § Phase 1
├─ Reference: darwin-critical-edge-cases.md § Edge Case 1 (detection)
├─ Run: darwin-verification-queries.md §§ 6-10 (post-change tests)
└─ Verify: NixOS still builds before committing

PHASE 2: DARWIN FLAKE & MODULES
├─ Follow: darwin-activation-checklist.md § Phases 2-3
├─ Run: darwin-verification-queries.md §§ 11-17 (post-module tests)
└─ Commit when all evaluations pass

PHASE 3: BOOTSTRAP & BUILD SCRIPTS
├─ Follow: darwin-activation-checklist.md § Phase 4
├─ Reference: darwin-critical-edge-cases.md § Edge Case 2 (idempotency)
└─ Test: bootstrap-darwin script (scenario A, B, C, D, E)

PHASE 4: FIRST ACTIVATION
├─ Reference: darwin-activation-checklist.md § Activation Sections 1-4
├─ Reference: darwin-critical-edge-cases.md § Edge Cases 2-3
├─ Follow: darwin-activation-checklist.md § Activation 2 (first switch specifics)
└─ If fails: Read Emergency Procedures

POST-ACTIVATION (5 MIN)
├─ Run: darwin-verification-queries.md § Post-Activation (1-hour checks)
└─ Follow: darwin-activation-checklist.md § Post-Activation Verification

POST-ACTIVATION (24 HOURS)
├─ Run: darwin-verification-queries.md § 24-hour Monitoring
└─ Follow: darwin-activation-checklist.md § Monitoring Phase

REGRESSION TESTING
├─ Run: darwin-verification-queries.md § Regression Testing
└─ Verify: NixOS unaffected (§ 28-32)

IF SOMETHING BREAKS
├─ Identify: Use darwin-critical-edge-cases.md (which edge case?)
├─ Diagnose: Use darwin-verification-queries.md (Emergency section)
├─ Recover: Use darwin-activation-checklist.md (Emergency Procedures)
└─ Prevent: Document in plan/CLAUDE.md for future
```

---

## Key Invariants to Protect

These data invariants must remain true before, during, and after activation:

| Invariant | Check | Document |
|-----------|-------|----------|
| NixOS nix.gc uses `dates = "weekly"` | `nix eval .#nixosConfigurations.thinkpad.config.nix.gc.dates` | VQ #8 |
| NixOS `auto-optimise-store = true` | `nix eval .#nixosConfigurations.thinkpad.config.nix.settings.auto-optimise-store` | VQ #9 |
| Darwin `auto-optimise-store = false` | `nix eval .#darwinConfigurations.macbook-pro.config.nix.settings.auto-optimise-store` | VQ #14 |
| Darwin gc uses `interval` (launchd) | `nix eval .#darwinConfigurations.macbook-pro.config.nix.gc.interval` | VQ #13 |
| Shell aliases in `home.shellAliases` | `nix eval '.#nixosConfigurations.thinkpad.config.home-manager.users.javels.home.shellAliases'` | VQ #3 |
| Home-manager routing: `/home` on Linux | `nix eval '.#nixosConfigurations.thinkpad.config.home-manager.users.javels.home.homeDirectory'` | VQ #16 |
| Home-manager routing: `/Users` on Darwin | Manual test on macOS | VQ #16 |
| Homebrew casks: 9 expected | `brew list --cask \| wc -l` | VQ #20 |
| Aerospace keybindings present | `grep "alt-h" ~/.config/aerospace/aerospace.toml` | VQ #24 |
| Stylix targets explicit (not auto) | `nix eval .#darwinConfigurations.macbook-pro.config.stylix.autoEnable` | VQ #18 |

---

## Critical Path (Minimum Viable Verification)

If time is limited, perform these **minimum** checks:

**Before Implementation:**
- [ ] Save baselines (VQ #1-3): `nix eval .#nixosConfigurations.thinkpad.config.nix.gc` → save to `/tmp/nixos-gc-baseline.json`
- [ ] Verify NixOS builds: `nixos-rebuild dry-build --flake ~/nix-config#thinkpad` → no errors

**After Shared Module Change:**
- [ ] Verify lib.mkIf syntax: `grep "lib.mkIf pkgs.stdenv.isLinux" ~/nix-config/modules/shared/nix.nix`
- [ ] Test NixOS eval: `nix eval .#nixosConfigurations.thinkpad.config.nix.gc.dates --json` → should be `"weekly"`
- [ ] Compare with baseline: `diff /tmp/nixos-gc-baseline.json /tmp/nixos-gc-after.json` → should be identical

**After Module Creation:**
- [ ] Verify Darwin evaluates: `nix eval .#darwinConfigurations.macbook-pro.config.system.build.toplevel --json` → no errors
- [ ] Verify all files exist: `test -f ~/nix-config/hosts/macbook-pro/default.nix && echo OK` (× 9 files)

**After First Activation (5 min):**
- [ ] System defaults applied: `defaults read com.apple.dock autohide` → should be `1`
- [ ] Homebrew casks installed: `brew list --cask | wc -l` → should be ≥ 9
- [ ] home-manager active: `home-manager generations | head -1` → shows generation

**At 24 Hours:**
- [ ] No system crashes: `uptime` shows > 24h without reboot
- [ ] Rebuild is fast: `bash apps/build-switch-darwin` completes in < 10 min
- [ ] NixOS still builds: `nixos-rebuild dry-build --flake ~/nix-config#thinkpad` → no errors

---

## File Locations

**All checklist files are in:**
```
~/nix-config/docs/checklists/
├── 2026-03-04-darwin-activation-checklist.md          (main activation guide)
├── 2026-03-04-darwin-critical-edge-cases.md           (edge case deep dives)
├── 2026-03-04-darwin-verification-queries.md          (executable queries)
└── README.md                                            (this file)
```

**Reference from CLAUDE.md after Darwin is implemented:**
```markdown
## Darwin Activation & Troubleshooting

See `docs/checklists/` for:
- `2026-03-04-darwin-activation-checklist.md` — Full activation guide
- `2026-03-04-darwin-critical-edge-cases.md` — Edge case analysis
- `2026-03-04-darwin-verification-queries.md` — Verification queries

Key invariants to maintain:
- NixOS: nix.gc.dates = "weekly", auto-optimise-store = true
- Darwin: nix.gc.interval = [Hour=4, Minute=0], auto-optimise-store = false
```

---

## Document Maintenance

These checklists are **living documents**. Update them:

- **After first Darwin activation:** Document any unexpected issues found
- **After NixOS changes:** Verify shared module conditionals still work
- **After Homebrew cask changes:** Update the expected cask count in VQ #20
- **After bootstrap script changes:** Add new idempotency tests to Edge Case 2

All changes should be committed with reference to the actual issue/PR.

---

## Version History

| Date | Scope | Reference |
|------|-------|-----------|
| 2026-03-04 | Initial creation for Darwin implementation plan | `docs/plans/2026-03-04-feat-macos-darwin-configuration-plan.md` |

---

**Last Updated:** 2026-03-04
**Status:** Active — Ready for Phase Implementation
**Owner:** Deployment Verification Agent
