{ pkgs, ... }:
{
  services.xserver.xkb = {
    layout = "de";
    variant = "nodeadkeys";
  };

  # NixOS hosts here are always personal machines; the work PC uses
  # system-manager instead.
  programs.kdeconnect.enable = true;

  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
  ];
}
