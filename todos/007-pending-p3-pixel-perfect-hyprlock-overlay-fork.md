---
status: pending
priority: p3
issue_id: "007"
tags: [hyprlock, cua, agent-mode, lock-screen, refactor, cpp-patch]
dependencies: []
---

# Pixel-Perfect Agent-Mode Curtain via a Patched hyprlock (one service, not two)

## Problem Statement

The cua agent-mode lock (R17) shows a curtain on the physical output while the real
desktop lives on an off-screen stage. We want that curtain to look **identical** to
hyprlock. The maintainable, pixel-perfect way is to **reuse hyprlock itself** — patch
it to add a non-locking "overlay" mode that renders its exact scene onto a layer-shell
surface (no `ext-session-lock`, no auth, single physical output). One binary, one
config, zero scene duplication.

**Deferred** in favor of the lighter "separate services" approach (an AGS window that
replicates hyprlock's scene — see `home/linux/ags/widgets/AgentLock.tsx`), because the
fork is a MODERATE C++ project. Pick this up when the AGS replica's drift/maintenance
cost justifies unifying, or to upstream the mode.

Full requirements: `docs/brainstorms/2026-06-28-unified-lock-curtain-requirements.md`.

## Findings (hyprlock v0.9.2 source, commit c48279d1 — feasibility = MODERATE)

The load-bearing question — can hyprlock render its scene without acquiring the
session lock — is **YES**. The renderer is already lock-agnostic; the cost is that
there is **zero layer-shell plumbing to reuse** (it must be vendored + added).

- **Renderer is fully separable.** `CRenderer::renderLock` (`src/renderer/Renderer.cpp:201-233`)
  only reads `surf.size`, `surf.eglSurface`, `surf.m_outputID`, `surf.m_outputRef`; widgets
  are keyed by output ID (`:395-431`). It never touches `ext_session_lock`. (This is the win.)
- **Auth is a clean skip.** Constructed/started only in `run()` (`src/core/hyprlock.cpp:335-336`),
  invoked only on keypress (`:702`); the render loop never calls it. Display-only = don't
  call `g_pAuth->start()`, don't add the input-field widget.
- **Lock acquisition is isolated** to `acquireSessionLock()` (`src/core/hyprlock.cpp:782-812`),
  called from one line (`:389`); startup hard-fail at `:325-328`.
- **No layer-shell anywhere.** Registry binds 10 interfaces (`src/core/hyprlock.cpp:257-295`);
  surfaces are created only as lock surfaces (`src/core/LockSurface.cpp:50` `sendGetLockSurface`).
  (Note: the binary does NOT bind `zwlr_layer_shell_v1` — that v5 global is advertised by
  Hyprland; hyprlock binds `zwlr_screencopy_manager_v1 v3` for `background:screenshot`.)
- **Always all outputs** (`m_vOutputs`, `:804-809`), but per-output structure makes a
  single-output filter a small loop change, not architectural.

## Minimal patch sketch

1. `src/main.cpp` — add `--overlay` bool (mirror `--no-fade-in`, ~:104); thread into the `CHyprlock` ctor.
2. `src/core/hyprlock.{hpp,cpp}` — store `m_bOverlay`; bind `zwlr_layer_shell_v1` in the registry; when overlay: soften the session-lock hard-fail (`:325-328`), skip `g_pAuth->start()` (`:336`), replace `acquireSessionLock()` (`:389`) with a per-output layer-surface loop, and on fade-out set `m_bTerminate` instead of `releaseSessionLock()`.
3. `CMakeLists.txt` — vendor `wlr-layer-shell-unstable-v1.xml` + `protocolnew(...)` (like `wlr-screencopy`).
4. New surface path — branch `CSessionLockSurface` or add a sibling `CLayerSurface` exposing the same `{size, eglSurface, m_outputID, m_outputRef, render()}` and calling `g_pRenderer->renderLock(*this)`. Configure fullscreen layer surface: anchor all 4 edges, `set_exclusive_zone(-1)`, `keyboard_interactivity = none`, layer OVERLAY/TOP, namespace `"hyprlock-overlay"`; build egl exactly as `src/core/LockSurface.cpp:85-94`.
5. Package via `pkgs.hyprlock.overrideAttrs { patches = [ ./hyprlock-overlay.patch ]; }`; cua daemon spawns `hyprlock --overlay --config <…>` in place of the kitty curtain (`cua-daemon.py` `_agentmode_enter`/`_agentmode_teardown`).

## Top risks

- **Signature churn:** `renderLock`/`getOrCreateWidgetsFor`/widget `configure` take `const CSessionLockSurface&` — needs a shared base/interface or the 4 fields duplicated (mechanical).
- **Protocol vendoring:** `wlr-layer-shell` isn't in `wayland-protocols`; `get_popup` references `xdg_popup`, so `hyprwayland-scanner` may need `xdg-shell` vendored too. Build-time risk.
- **EGL on hybrid GPU (this machine):** a layer-shell EGL surface may hit the same blank-paint failure that blanks AGS layer-shell when GL lands on the suspended NVIDIA dGPU (see `[[ags-popups-blank-hybrid-gpu]]`). **Verify with a minimal paint spike first.** (The AGS replica sidesteps this — it's software-rendered.)
- **Fade-out callback** (`src/renderer/Renderer.cpp:618`) hard-calls `releaseSessionLock()` — must be conditionalized or it asserts.
- **Patch maintenance:** rebasing on upstream hyprlock; consider upstreaming a render-only mode.
