---
status: pending
priority: p2
issue_id: "005"
tags: [do-nixbox, tailscale, docker, services]
dependencies: ["do-nixbox host deployed"]
---

# Add Tailscale and Docker to Do-nixbox

## Problem Statement

Do-nixbox was deployed with SSH-only access as the initial scope. Two services were explicitly deferred for a follow-up iteration:

1. **Tailscale** — VPN mesh networking to thinkpad and macbook-pro. Enables private access without exposing ports to the public internet. Adds a hardening layer.
2. **Docker** — For running containerized agent tools, MCP servers, and other services.

## Proposed Solution

### Tailscale
- Add `services.tailscale.enable = true` to `hosts/do-nixbox/default.nix`
- Decide on auth key management: manual `tailscale up` post-deploy, sops-nix, or pre-auth key
- Consider restricting SSH to Tailscale interface only (close port 22 on public IP)

### Docker
- Add `virtualisation.docker.enable = true` to `hosts/do-nixbox/default.nix`
- Add `${user}` to `docker` group
- Consider rootless Docker for security (`virtualisation.docker.rootless.enable`)

## Acceptance Criteria

- [ ] `tailscale status` shows do-nixbox connected to tailnet
- [ ] Can SSH to do-nixbox via Tailscale IP from thinkpad/macbook-pro
- [ ] `docker run hello-world` succeeds on do-nixbox
- [ ] Firewall updated: SSH via Tailscale only (port 22 closed on public interface)

## Technical Details

- **Affected files:** `hosts/do-nixbox/default.nix`, `flake.nix` (if Tailscale needs a flake input)
- **Origin:** Deferred from brainstorm (see `docs/brainstorms/2026-03-05-do-nixbox-droplet-brainstorm.md`)

## Implementation Status (2026-06-29)

Declarative config landed in `hosts/do-nixbox/default.nix` and **builds clean**
(`nixos-rebuild build --flake .#do-nixbox`, x86_64-linux):

- **Tailscale** — `services.tailscale.enable` (1.90.9) + `openFirewall` (UDP 41641)
  + `useRoutingFeatures = "client"`; `networking.firewall.trustedInterfaces =
  [ "tailscale0" ]` so SSH-over-tailnet works (and the future port-22 cutover is
  just dropping 22). **Auth is manual** (no secret mgmt): run `sudo tailscale up`
  once on the box.
- **Docker** — rootful, `${user}` added to the `docker` group. Pinned
  `virtualisation.docker.package = pkgs.docker_29` (29.5.3): the default `docker`
  is 28.5.2, which 25.11 marks **insecure** (docker_28 unmaintained since Nov 2025)
  — caught at build time; pinned rather than permitting the insecure package.

Remaining (all on-box — cannot be verified from the dev machine):

- [ ] Deploy (push to main → 04:00 auto-upgrade, or `nixos-rebuild --target-host`).
- [ ] `sudo tailscale up` on the droplet; confirm `tailscale status` on the tailnet.
- [ ] SSH to do-nixbox via its Tailscale IP from thinkpad/macbook-pro.
- [ ] `docker run hello-world`.
- [ ] **Then** stage AC#4 in a follow-up: drop `22` from `allowedTCPPorts`
      (SSH-via-tailnet only) — only after the above is confirmed, so the
      auto-upgrade can't lock the box out.
