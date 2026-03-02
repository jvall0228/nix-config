{ ... }:
{
  programs.starship.settings = {
    format = "$os$directory$git_branch$git_status$character";
    os = {
      disabled = false;
      symbols.NixOS = " ";
    };
    directory.style = "blue bold";
    git_branch.style = "purple";
    character = {
      success_symbol = "[❯](blue)";
      error_symbol = "[❯](red)";
    };
  };
}
