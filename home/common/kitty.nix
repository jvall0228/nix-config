{ ... }:
{
  programs.kitty = {
    enable = true;
    settings = {
      font_size = 14;
      window_padding_width = 8;
      confirm_os_window_close = 0;
      enable_audio_bell = false;
      scrollback_lines = 10000;
    };
  };
}
