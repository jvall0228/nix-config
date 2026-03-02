{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    extraPackages = with pkgs; [
      lua-language-server
      pyright
      rust-analyzer
      typescript-language-server
      nil

      stylua
      black
      nodePackages.prettier
    ];
  };
}
