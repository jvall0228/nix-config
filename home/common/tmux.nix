{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    shell = "${pkgs.bash}/bin/bash";
    keyMode = "vi";
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 10000;
    mouse = true;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      vim-tmux-navigator
      tokyo-night-tmux
    ];
    extraConfig = ''
      set -g status-position top
      set -ag terminal-overrides ",xterm-256color:RGB"
    '';
  };
}
