{ inputs, ... }:
{
  imports = [ inputs.walker.homeManagerModules.walker ];

  programs.walker = {
    enable = true;
    runAsService = true;

    config = {
      close_when_open = true;
      click_to_close = true;
      single_click_activation = true;
      theme = "tokyo-night";
      as_window = false;

      shell = {
        layer = "overlay";
        anchor_top = true;
        anchor_bottom = true;
        anchor_left = true;
        anchor_right = true;
      };

      placeholders."default" = {
        input = "Search...";
        list = "No Results";
      };

      keybinds = {
        close = [ "Escape" ];
        next = [ "Down" ];
        previous = [ "Up" ];
      };

      providers = {
        default = [ "desktopapplications" "calc" "websearch" ];
        empty = [ "desktopapplications" ];
        max_results = 50;

        prefixes = [
          { prefix = ";"; provider = "providerlist"; }
          { prefix = ">"; provider = "runner"; }
          { prefix = "/"; provider = "files"; }
          { prefix = "."; provider = "symbols"; }
          { prefix = "="; provider = "calc"; }
          { prefix = "@"; provider = "websearch"; }
          { prefix = ":"; provider = "clipboard"; }
          { prefix = "$"; provider = "windows"; }
        ];
      };
    };

    themes."tokyo-night" = {
      style = ''
        /* Tokyo Night Dark — base16 colors from Stylix */
        @define-color bg #1a1b26;
        @define-color bg_light #16161e;
        @define-color selection #2f3549;
        @define-color comment #444b6a;
        @define-color fg_dim #787c99;
        @define-color fg #a9b1d6;
        @define-color fg_light #cbccd1;
        @define-color accent #7aa2f7;
        @define-color green #9ece6a;
        @define-color cyan #b4f9f8;
        @define-color blue #2ac3de;
        @define-color purple #bb9af7;
        @define-color red #f7768e;

        .box-wrapper {
          background: @bg;
          border: 1px solid alpha(@accent, 0.3);
          border-radius: 16px;
          padding: 16px;
          box-shadow: 0 8px 32px alpha(black, 0.4);
        }

        .input {
          background: @bg_light;
          padding: 12px 16px;
          border-radius: 8px;
          border: 1px solid @selection;
          color: @fg;
          caret-color: @accent;
          font-family: "Noto Sans", sans-serif;
          font-size: 16px;
        }

        .input:focus {
          border-color: alpha(@accent, 0.5);
        }

        .list {
          margin-top: 8px;
        }

        .item-box {
          border-radius: 8px;
          padding: 8px 12px;
          color: @fg;
        }

        child:selected .item-box,
        row:selected .item-box {
          background: alpha(@accent, 0.15);
        }

        .item-text {
          font-family: "Noto Sans", sans-serif;
          font-size: 14px;
          color: @fg;
        }

        .item-subtext {
          font-family: "Noto Sans", sans-serif;
          font-size: 12px;
          color: @fg_dim;
        }

        .item-image {
          margin-right: 8px;
        }

        .item-quick-activation {
          font-family: "JetBrainsMono Nerd Font", monospace;
          font-size: 11px;
          color: @comment;
          background: @selection;
          border-radius: 4px;
          padding: 2px 6px;
        }

        .placeholder {
          color: @comment;
          font-style: italic;
        }

        .keybinds {
          margin-top: 8px;
          padding-top: 8px;
          border-top: 1px solid @selection;
        }

        .keybind-label {
          color: @fg_dim;
          font-size: 11px;
        }

        .keybind-bind {
          color: @accent;
          font-family: "JetBrainsMono Nerd Font", monospace;
          font-size: 11px;
        }

        .error {
          color: @red;
        }

        .calc .item-text {
          color: @green;
          font-family: "JetBrainsMono Nerd Font", monospace;
        }

        .symbols .item-image-text {
          font-size: 24px;
        }

        .elephant-hint {
          color: @comment;
          font-size: 12px;
        }
      '';
    };
  };
}
