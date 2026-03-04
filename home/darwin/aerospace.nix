{ ... }:
{
  # Aerospace is installed via Homebrew cask (modules/darwin/core.nix)
  # Config is written directly as TOML since programs.aerospace doesn't exist in home-manager 25.11
  home.file.".aerospace.toml".text = ''
    # Aerospace tiling window manager configuration
    # Keybindings mirror Hyprland setup for cross-platform muscle memory

    enable-normalization-flatten-containers = false
    enable-normalization-opposite-orientation-for-nested-containers = false
    on-focused-monitor-changed = ["move-mouse monitor-lazy-center"]

    default-root-container-layout = "tiles"
    default-root-container-orientation = "auto"
    accordion-padding = 30

    [gaps]
    inner.horizontal = 8
    inner.vertical = 8
    outer.left = 8
    outer.right = 8
    outer.top = 8
    outer.bottom = 8

    [key-mapping]
    preset = "qwerty"

    [mode.main.binding]
    # Focus (alt + hjkl — mirrors Hyprland movefocus)
    alt-h = "focus left"
    alt-j = "focus down"
    alt-k = "focus up"
    alt-l = "focus right"

    # Move windows (alt+shift + hjkl)
    alt-shift-h = "move left"
    alt-shift-j = "move down"
    alt-shift-k = "move up"
    alt-shift-l = "move right"

    # Layout
    alt-f = "fullscreen"
    alt-shift-space = "layout floating tiling"
    alt-s = "layout v_accordion"
    alt-w = "layout h_accordion"
    alt-e = "layout tiles horizontal vertical"

    # Resize
    alt-shift-minus = "resize smart -50"
    alt-shift-equal = "resize smart +50"

    # Workspaces (alt+N — mirrors Hyprland workspace binds)
    alt-1 = "workspace 1"
    alt-2 = "workspace 2"
    alt-3 = "workspace 3"
    alt-4 = "workspace 4"
    alt-5 = "workspace 5"
    alt-6 = "workspace 6"
    alt-7 = "workspace 7"
    alt-8 = "workspace 8"
    alt-9 = "workspace 9"
    alt-0 = "workspace 10"

    # Move to workspace (alt+shift+N)
    alt-shift-1 = "move-node-to-workspace 1"
    alt-shift-2 = "move-node-to-workspace 2"
    alt-shift-3 = "move-node-to-workspace 3"
    alt-shift-4 = "move-node-to-workspace 4"
    alt-shift-5 = "move-node-to-workspace 5"
    alt-shift-6 = "move-node-to-workspace 6"
    alt-shift-7 = "move-node-to-workspace 7"
    alt-shift-8 = "move-node-to-workspace 8"
    alt-shift-9 = "move-node-to-workspace 9"
    alt-shift-0 = "move-node-to-workspace 10"

    # Misc
    alt-shift-c = "reload-config"
    alt-r = "mode resize"

    [mode.resize.binding]
    h = "resize width -50"
    j = "resize height +50"
    k = "resize height -50"
    l = "resize width +50"
    enter = "mode main"
    esc = "mode main"

    # Window rules
    [[on-window-detected]]
    if.app-id = "com.apple.systempreferences"
    run = "layout floating"
  '';
}
