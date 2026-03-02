{ ... }:
{
  services.swaync = {
    enable = true;
    settings = {
      positionX = "right";
      positionY = "top";
      control-center-width = 400;
      notification-window-width = 400;
      notification-icon-size = 48;
      fit-to-screen = true;
      hide-on-clear = true;
    };
  };
}
