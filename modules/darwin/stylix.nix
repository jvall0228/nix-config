{ ... }:
{
  imports = [ ../shared/stylix.nix ];

  # Most stylix targets (waybar, hyprlock, GTK, QT) don't exist on Darwin.
  # HM-level targets (kitty, bat, btop) are themed via stylix.homeManagerIntegration
  # which has its own autoEnable independent of this system-level setting.
  stylix.autoEnable = false;
}
