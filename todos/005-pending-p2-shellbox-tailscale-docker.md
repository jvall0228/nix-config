---
status: pending
priority: p2
issue_id: "005"
tags: [shellbox, tailscale, docker, services]
dependencies: ["shellbox host deployed"]
---

# Add Tailscale and Docker to Shellbox

## Problem Statement

Shellbox was deployed with SSH-only access as the initial scope. Two services were explicitly deferred for a follow-up iteration:

1. **Tailscale** — VPN mesh networking to thinkpad and macbook-pro. Enables private access without exposing ports to the public internet. Adds a hardening layer.
2. **Docker** — For running containerized agent tools, MCP servers, and other services.

## Proposed Solution

### Tailscale
- Add `services.tailscale.enable = true` to `hosts/shellbox/default.nix`
- Decide on auth key management: manual `tailscale up` post-deploy, sops-nix, or pre-auth key
- Consider restricting SSH to Tailscale interface only (close port 22 on public IP)

### Docker
- Add `virtualisation.docker.enable = true` to `hosts/shellbox/default.nix`
- Add `${user}` to `docker` group
- Consider rootless Docker for security (`virtualisation.docker.rootless.enable`)

## Acceptance Criteria

- [ ] `tailscale status` shows shellbox connected to tailnet
- [ ] Can SSH to shellbox via Tailscale IP from thinkpad/macbook-pro
- [ ] `docker run hello-world` succeeds on shellbox
- [ ] Firewall updated: SSH via Tailscale only (port 22 closed on public interface)

## Technical Details

- **Affected files:** `hosts/shellbox/default.nix`, `flake.nix` (if Tailscale needs a flake input)
- **Origin:** Deferred from brainstorm (see `docs/brainstorms/2026-03-05-shellbox-droplet-brainstorm.md`)
