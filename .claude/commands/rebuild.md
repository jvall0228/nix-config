Run `bash apps/build-switch` to rebuild the NixOS system configuration.

After the rebuild completes, verify system health with `systemctl is-system-running`.

If the rebuild fails, check logs with `journalctl -u nixos-rebuild.service -n 100`.
