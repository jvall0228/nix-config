{ config, pkgs, user, ... }:
let
  hostname = config.networking.hostName;
  release = config.system.nixos.release;
  stateVersion = config.system.stateVersion;

  # Local NixOS modules imported for this host (hardcoded — one host, known imports)
  enabledModules = builtins.concatStringsSep "\n" [
    "- modules/nixos/core.nix"
    "- modules/nixos/audio.nix"
    "- modules/nixos/nvidia.nix"
    "- modules/nixos/hyprland.nix"
    "- modules/nixos/power.nix"
    "- modules/nixos/stylix.nix"
    "- modules/nixos/greetd.nix"
    "- modules/nixos/agent-context.nix"
  ];
in
{
  system.activationScripts.agentContext.text = ''
    _agent_context_generate() {
      local kernel gpu timestamp
      kernel="$(${pkgs.coreutils}/bin/uname -r)"
      gpu="$(${pkgs.pciutils}/bin/lspci 2>/dev/null | ${pkgs.gnugrep}/bin/grep -i vga || echo "unknown")"
      timestamp="$(${pkgs.coreutils}/bin/date -Iseconds)"

      ${pkgs.coreutils}/bin/cat > /etc/agent-context.md.tmp << CTXEOF
    # System Context — ${hostname}
    Generated: $timestamp

    ## System
    - NixOS ${release}, x86_64-linux, kernel $kernel
    - Flake: ~/nix-config#${hostname}
    - GPU: $gpu

    ## Configuration Paths
    - Flake entry point: flake.nix
    - Host config: hosts/${hostname}/default.nix
    - System packages: modules/nixos/core.nix (environment.systemPackages)
    - User packages: home/common/dev-tools.nix (home.packages)
    - Shell/aliases: home/common/shell.nix
    - Desktop/Hyprland: home/linux/hyprland.nix
    - Theming: modules/nixos/stylix.nix

    ## Enabled Modules
    ${enabledModules}

    ## System Packages (core.nix)
    curl, file, git, htop, sbctl, unzip, wget

    ## User Packages (dev-tools.nix)
    bat, claude-code, codex, eza, fd, fzf, gemini-cli, gh, jq, lazygit, nodejs, opencode, python3, ripgrep, rustup

    ## AI Agent Status (live, queryable)
    - A user daemon (home/linux/agent-status.nix) reports which AI coding agents are
      running (claude, codex, gemini, opencode) and each running agent's latest
      user/assistant message. It rescans every 1s.
    - It publishes \$XDG_RUNTIME_DIR/agent-status.json. Query it with the
      "agent-status" command (also: agent-status --json, agent-status <name>), or read
      the JSON directly with jq.
    - Consumers: the Hyprland lock screen (home/linux/hyprlock.nix JRPG widget) and the
      waybar agent indicator (home/linux/waybar.nix custom/agent) both read this file —
      anything else can too.
    - Service: systemctl --user status agent-status. Schema + how to add an agent:
      docs/agent-status.md

    ## Constraints
    - Do NOT edit hardware-configuration.nix manually
    - Do NOT change system.stateVersion or home.stateVersion (currently ${stateVersion})
    - Do NOT hardcode usernames — use the user variable (currently "${user}")
    - Do NOT add NixOS-specific options in home/common/ (use home/linux/)
    - Lanzaboote: 10 bootloader generation limit — run bash apps/clean between major rebuild batches
    - Auto-upgrade: 04:00 from github:jvall0228/nix-config/main — commit and push before expecting persistence
    CTXEOF

      ${pkgs.coreutils}/bin/chmod 0644 /etc/agent-context.md.tmp
      ${pkgs.coreutils}/bin/mv /etc/agent-context.md.tmp /etc/agent-context.md
    }

    if ! _agent_context_generate; then
      echo "WARNING: agent-context generation failed" | ${pkgs.systemd}/bin/systemd-cat -t agent-context -p warning
    fi
  '';
}
