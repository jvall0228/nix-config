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
