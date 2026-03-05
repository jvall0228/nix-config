# Brainstorm: CLI Tool Version Pinning

**Date:** 2026-03-05
**Status:** Ready for planning

## What We're Building

A Nix overlay that pins AI CLI tools (claude-code, codex, gemini-cli, opencode) to their latest upstream versions, bypassing nixpkgs-unstable lag. Paired with an update script (`apps/update-cli-tools`) that automates version bumps.

## Why This Approach

nixpkgs-unstable lags behind fast-moving npm-based CLI tools. Codex was 18 minor versions behind (0.92.0 vs 0.110.0). Rather than installing via npm directly (losing Nix reproducibility) or writing custom derivations from scratch (over-engineering), we override the existing nixpkgs derivations with pinned versions and hashes.

An update script prevents falling behind again — the manual hash-computation friction is what caused the current staleness.

## Version Gaps (as of 2026-03-05)

| Tool | Installed (unstable) | Latest upstream | Source |
|------|---------------------|----------------|--------|
| claude-code | 2.1.59 | 2.1.69 | npm: @anthropic-ai/claude-code |
| codex | 0.92.0 | 0.110.0 | npm: @openai/codex |
| gemini-cli | 0.30.0 | 0.32.1 | npm: @google/gemini-cli |
| opencode | 1.2.13 | ~1.2.6 | GitHub: opencode-ai/opencode (Go binary) |

## Key Decisions

- **Scope:** All four AI CLI tools, for consistency.
- **Strategy:** Nix overlay with version overrides + automated update script.
- **Overlay location:** `overlays/cli-tools.nix` (new file).
- **Update script location:** `apps/update-cli-tools` (new file, fits existing `apps/` pattern).
- **Package source:** Override `version` and `src` on existing nixpkgs derivations. For npm packages, fetch tarballs from the npm registry. For opencode (Go binary), fetch from GitHub releases.
- **Integration:** The overlay applies to the `unstable` package set so `unstable.claude-code` etc. automatically use the pinned versions.

## Approach Alternatives Considered

1. **npm/pip direct install** — Rejected. Loses Nix reproducibility and declarative management.
2. **fetchurl custom derivations** — Rejected. Over-engineered; existing nixpkgs derivations work fine, just need version bumps.
3. **Manual pin only (no script)** — Rejected. Too much friction to update hashes manually; would lead to the same staleness problem.

## Open Questions

None — all decisions resolved during brainstorming.
