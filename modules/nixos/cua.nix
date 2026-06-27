{ user, ... }:
{
  # ── uinput access for the computer-use-agent (cua) stack ───────────────────
  # The cua daemon drives a *user-level* ydotoold (home/linux/cua.nix), which
  # must open /dev/uinput to synthesize input. A non-root process can't do that
  # by default, so grant it via a deterministic group+mode udev rule and put the
  # user in the `input` group. We use the group/mode rule (not the uaccess ACL)
  # because the ACL is tied to an active seat login and is unreliable for a
  # user systemd service; the group rule is stable across re-logins.
  #
  # This is also what the optional EVIOCGRAB hard-lockout helper needs, so the
  # one privilege grant pays for both perception/action and lockout.
  #
  # SECURITY TRADEOFF: `input`-group membership confers read access to every
  # /dev/input/event* device — i.e. system-wide keylogging capability. This is
  # an intentional loosening of this host's otherwise-hardened posture
  # (modules/nixos/core.nix), accepted because thinkpad is a single-user,
  # LUKS-encrypted workstation. Do NOT enable this module on a multi-user host.
  # See docs/cua.md.
  boot.kernelModules = [ "uinput" ];

  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
  '';

  # Merged (list-concatenated) with the extraGroups set in core.nix — no edit to
  # the hardened core module needed. Requires one logout/login to take effect.
  users.users.${user}.extraGroups = [ "input" ];
}
